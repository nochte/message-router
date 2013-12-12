require 'timeout'
require 'json'
require 'yaml'
require 'onstomp'
require 'spawnling'
require 'timeout'
include Util

module Message
  module Worker
    class DeadWorkerException < Exception; end
    include OnStomp

    class Base
      attr_accessor :worker_queue, :worker_dequeue_method
      attr_reader :command_thread, :state, :monitor_thread, :last_worker_spawned_at, :subscribed_incoming_queue

      MINIMUM_RESULTS_TO_KEEP = 20
      MINIMUM_STATUS_METRICS_TO_KEEP = 10
      MONITOR_THREAD_RESPAWN_TIME = 1
      WORKER_STATUS_POLLING_INTERVAL = 5
      WORKER_SPAWNING_INTERVAL = 120 #seconds
      DEFAULT_MINIMUM_WORKERS = 1
      DEFAULT_MAXIMUM_WORKERS = 5

      @is_persistent = true
      @subscribed_incoming_queue = nil

      #override this method
      #note: if a message is passed in, then the return should be
      #  the specific queue that the message is destined for
      def worker_queue_attributes message = nil
        @queue ||= []
        {:queue => @queue, :dequeue => :pop, :enqueue => :push}
      end

      #override this method
      def process_job job
        raise "Not implemented yet. This is where you implement your business logic"
      end

      #override this method if you want to handle routing yourself
      def on_incoming_message message
        enqueue_message JSON.parse(message) rescue log :error, "Failed to parse: #{message}"
      end


      #generic methods

      def initialize args = {:router => false, :worker => true}
        args[:command] ||= STDIN
        args[:status] ||= STDOUT
        @start_time = Time.now
        @state = :initializing
        @nature = :eunuch
        if args[:worker]
          @nature = :worker
          @messages_processed = 0
          @last_status_at = Time.now
          @command_pipe = args[:command]
          @status_pipe = args[:status]
          @messages_processed_results = [] #we're going to hold timings in this here array
          @command_thread = start_command_thread
        end
        if args[:router]
          @nature = :router
          start_monitor_service_thread
          @command_pipe = args[:command]
          @status_pipe = args[:status]
          start_command_thread
          if self.class.subscribed_incoming_queue
            log :debug, "Connecting to #{incoming_queue}"
          end
        end
      end

      def enqueue_message message
        message = message.flatten if message.class == Array
        qa = worker_queue_attributes message
        qa[:queue].send(qa[:enqueue], message)
      end

      def dequeue_message
        @worker_queue.send(@worker_dequeue_method)
      end



      DEFAULT_CONFIG = {
          "test" => {
              "incoming_queues" => {
                  "test1" => '/queue/test1'
              },
              "connections" => {
                  "test1" => {
                      "host" => '127.0.0.1',
                      "login" => 'admin',
                      "passcode" => 'admin'
                  }
              },
              "workers" => {
                  "minimum" => 1,
                  "maximum" => 10
              }
          }
      }
      VALID_CONFIG_KEYS = DEFAULT_CONFIG.keys

      def self.configure opts = {}
        opts.each {|k,v| DEFAULT_CONFIG[::APP_ENV || "test"][k.to_sym] = v if VALID_CONFIG_KEYS.include? k.to_sym}
      end

      # Configure through yaml file
      def self.configure_with path_to_yaml_file
        config = DEFAULT_CONFIG[defined?(::APP_ENV) ? ::APP_ENV : "test"]
        begin
          config = YAML::load(IO.read(path_to_yaml_file))[defined?(::APP_ENV) ? ::APP_ENV : "test"]
        rescue Exception => ee
          log(:warning, "YAML configuration file couldn't be found. Using defaults. Specific error: #{ee.to_s}")
        end

        configure(config)
      end


      #router-specific methods

      def self.configuration
        path = defined?(::APP_ROOT) ? (File.join(::APP_ROOT, 'config/stomp.yml')) : nil
        @@configuration ||= configure_with(path)
      end

      def configuration
        @configuration ||= self.class.configuration
      end

      def minimum_workers
        configuration["workers"]["minimum"] || DEFAULT_MINIMUM_WORKERS rescue DEFAULT_MINIMUM_WORKERS
      end

      def maximum_workers
        configuration["workers"]["maximum"] || DEFAULT_MAXIMUM_WORKERS rescue DEFAULT_MAXIMUM_WORKERS
      end

      def incoming_queue
        @incoming_queue ||= connect_to_incoming_queue!
      end

      def start_worker *args
        @workers ||= {}
        name = "#{self.class} - #{@workers.length}"
        command_read, command_write = IO.pipe
        status_read, status_write = IO.pipe
        spawnling = Spawnling.new kill: true, argv: name do
          worker = self.class.new({ router: false, worker: true, command: command_read, status: status_write })
          worker.setup_worker
          worker.run_worker
        end

        register_worker spawnling.handle, {
            command: command_write,
            status: status_read,
            process: spawnling,
            process_name: name,
            success: true
        }
      end

      def worker_pids *_
        {:success => true, :workers => workers.keys, :workers_count => workers.count}
      end

      def register_worker id, worker
        @last_worker_spawned_at = Time.now
        @workers ||= {}
        @workers[id] = worker
      end

      def new_worker_needed?
        return true if last_worker_spawned_at.nil?
        return true if workers.length < minimum_workers
        return false if Time.now - last_worker_spawned_at < WORKER_SPAWNING_INTERVAL
        return false if workers.length >= maximum_workers
        status = worker_status
        return true if status[:average_idle_time_percentage] <= 30
        false
      end


      #worker-specific methods

      #do not override this unless you know what you're doing
      def setup_worker
        die if @state == :spinning_down
        @state = :initializing
        @queue_attributes = @worker_queue = @worker_dequeue_method = nil
        begin
          @queue_attributes = self.worker_queue_attributes
        end while @queue_attributes.nil?

        @worker_queue = @queue_attributes[:queue]
        @worker_dequeue_method = @queue_attributes[:dequeue]
        @state = :idle
      end

      def run_worker
        while 1
          job = get_next_job
          @state = :working
          work_time_start = Time.now
          process_job job
          log_results Time.now - work_time_start
        end
      end

      def get_next_job
        job = dequeue_message
        while job.nil?
          sleep 0.01 #throttles down the CPU
          self.setup_worker
          job = dequeue_message if @worker_queue
        end
        job
      end

      def long_running?
        self.class.is_persistent
      end

      def spin_down *args
        @state = :spinning_down
        { state: :spinning_down }
      end

      def status *args
        total_run_time = Time.now - @start_time
        total_process_time = @messages_processed_results.reduce(:+).to_f
        average_message_process_time = @messages_processed_results.length == 0 ? 0 : total_process_time / @messages_processed_results.length.to_f
        status_window = Time.now - @last_status_at
        idle_time = (status_window - total_process_time)
        idle_time_percentage = idle_time / status_window * 100

        @messages_processed_results.clear
        @last_status_at = Time.now

        {
            work_queue_size: @worker_queue.nil? ? 0 : @worker_queue.respond_to?(:length) ? @worker_queue.length : -1,
            average_message_process_time: average_message_process_time,
            total_run_time: total_run_time,
            total_messages_processed: @messages_processed,
            state: @state,
            timestamp: Time.now,
            idle_time: idle_time,
            idle_time_percentage: idle_time_percentage,
            pid: Process.pid,
            ok: true
        }
      end

      def terminate *args
        Thread.new do
          sleep 1
          exit 0
        end
        { success: true }
      end

      def worker_status *worker_pid
        worker_pid.flatten!
        if worker_pid.length > 0
          worker_pid = worker_pid[0].to_i
          return {:worker => worker_pid, :success => false, :error => "Worker not found"} unless workers.key?(worker_pid)
          return self.class.command_worker workers[worker_pid], "status"
        end
        seed = {
            average_work_queue_size: 0,
            average_message_process_time: 0,
            average_total_run_time: 0,
            average_messages_processed: 0,
            average_idle_time: 0,
            average_idle_time_percentage: 0
        }

        #this is so far beyond hacky. someone please put it out of its misery
        stats = workers.inject(seed) do |stats, worker_array|
          next (status) if worker_array.nil? || worker_array[1].nil? || worker_array[1][:status_history].nil?
          history_summary = ::Util.summarize_history worker_array[1][:status_history]
          stats[:average_work_queue_size] += history_summary["work_queue_size"] / workers.length rescue 0
          stats[:average_message_process_time] += history_summary["average_message_process_time"] / workers.length rescue 0
          stats[:average_total_run_time] += history_summary["total_run_time"] / workers.length rescue 0
          stats[:average_messages_processed] += history_summary["total_messages_processed"] / workers.length rescue 0
          stats[:average_idle_time_percentage] += history_summary["idle_time_percentage"] / workers.length rescue 100
          stats[:average_idle_time] += history_summary["idle_time"] / workers.length rescue 100
          stats
        end
        stats[:ok] = true
        stats
      end

      def workers
        @workers ||= {}
      end

      def last_worker_spawned_at
        @last_worker_spawned_at
      end

      protected
      def die
        exit 0
      end

      def log_results time
        @messages_processed_results << time
        @messages_processed += 1
      end

      COMMAND_MAP = {
          eunuch: {}, #default is no actions available
          router: {
              "spawn_worker" => :start_worker,
              "start_worker" => :start_worker,
              "kill_worker" => :clean_worker!,
              "worker_pids" => :worker_pids,
              "status" => :worker_status,
              "worker_status" => :worker_status,
              "enqueue" => :enqueue_message
          },
          worker: {
              "status" => :status,
              "spin_down" => :spin_down,
              "terminate" => :terminate,
              "enqueue" => :enqueue_message
          }
      }
      def start_command_thread
        @command_thread = Thread.new do
          while command = @command_pipe.gets.chomp
            retval = nil
            command, *args = command.split(' ')

            retval = process_command command, args
            @status_pipe.puts "#{retval.to_json}"
          end
        end
      end

      def process_command command, args
        begin
          send COMMAND_MAP[@nature][command.downcase], args
        rescue Exception => ee
          { error: "bad_input", command: command, args: args, :exception => ee.inspect}
        end
      end

      def self.log severity, message
        if !@logger.nil?
          @logger.log severity, message
        else
          tolog = "#{Time.now.to_s}: #{severity}: #{message}"
          puts tolog
        end
      end

      def log severity, message
        self.class.log severity, message
      end

      def connect_to_incoming_queue!
        incoming_queue = self.class.subscribed_incoming_queue rescue configuration['incoming_queues'].keys.first
        auth = configuration['connections'][incoming_queue]
        connection_string = "stomp://#{auth['login']}:#{auth['passcode']}@#{auth['host']}"
        client = OnStomp.connect(connection_string)
        client.subscribe(configuration['incoming_queues'][incoming_queue], :ack => 'client') do |message|
          client.ack message
          log :debug, message
          on_incoming_message message
        end
        client
      end

      def self.subscribes_to queue_name
        @subscribed_incoming_queue = queue_name
      end

      def self.subscribed_incoming_queue
        @subscribed_incoming_queue
      end

      def start_monitor_service_thread
        @monitor_service_thread = Thread.new do
          while true
            start_monitor_thread unless @monitor_thread && @monitor_thread.alive?
            sleep MONITOR_THREAD_RESPAWN_TIME
          end
        end
      end

      def start_monitor_thread
        @monitor_thread = Thread.new do
          while @workers.nil?
            log :debug, "Workers are nil"
            start_worker if new_worker_needed?
            sleep 1
          end
          while 1
            st = Time.now
            workers.each do |pid, worker_hash|
              begin
                fetch_status! worker_hash
              rescue DeadWorkerException => dwe
                log :error, "Got a dead worker: #{pid} :: #{worker_hash}"
                clean_worker! pid
              rescue Exception => ee
                log :error, "Got an unknown exception: #{ee}"
              end
            end
            et = Time.now
            log :info, "Fetched a status in #{et - st}"
            if new_worker_needed?
              log :info, "Starting a new worker"
              start_worker
            end
            sleep WORKER_STATUS_POLLING_INTERVAL
          end
        end
      end

      def fetch_status! worker
        begin
          Timeout::timeout(1) do
            (worker[:status_history] ||= []) << self.class.command_worker(worker, "status")
            if worker[:status_history].length > MINIMUM_STATUS_METRICS_TO_KEEP * 2
              worker[:status_history].slice!(0, (worker[:status_history].length - MINIMUM_STATUS_METRICS_TO_KEEP))
            end
          end
        rescue Exception => ee
          log :error, "Worker: ERRNO389: Exception thrown #{ee.to_s}"
          raise DeadWorkerException.new("Worker Unreachable")
        end
      end

      def clean_worker! worker_pid
        if worker_pid.class == Array
          worker_pid.flatten!
          res = {}
          res[:workers] = worker_pid.map do |pid|
            clean_worker! pid
          end
          res[:success] = true
          return res
        end
        worker_pid = worker_pid.to_i
        return {:worker => worker_pid, :success => false, :error => "Worker not found"} unless workers.key?(worker_pid)
        begin
          Process.kill("TERM", worker_pid)
        rescue Exception => ee
          log :error, "Worker: ERRNO398: Worker died through external means"
        end
        workers.delete worker_pid
        {:worker => worker_pid, :success => true}
      end


      def self.command_worker worker, command
        worker[:command].puts command
        ret = JSON.parse(worker[:status].gets)
        ret
      end
    end
  end
end
