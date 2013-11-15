require 'timeout'
require 'json'
require 'yaml'
require 'onstomp'

module Message
  module Worker
    include OnStomp


    class Base
      attr_accessor :worker_queue, :worker_dequeue_method
      attr_reader :command_thread, :state

      MINIMUM_RESULTS_TO_KEEP = 20
      @@is_persistent = false

      #override this method
      #note: if a message is passed in, then the return should be
      #  the specific queue that the message is destined for
      def get_worker_queue_attributes message = nil
        @queue ||= []
        {:queue => @queue, :dequeue => :pop, :enqueue => :push}
      end

      #override this method
      def process_job job
        raise "Not implemented yet. This is where you implement your business logic"
      end


      #generic methods

      def initialize args = {:router => false, :worker => true}
        @start_time = Time.now
        @state = :initializing
        @messages_processed = 0
        @messages_processed_results = [] #we're going to hold timings in this here array
        @command_thread = start_command_thread
      end

      def enqueue_message message
        qa = get_worker_queue_attributes message
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
              }
          }
      }
      VALID_CONFIG_KEYS = DEFAULT_CONFIG.keys

      def self.configure opts = {}
        opts.each {|k,v| DEFAULT_CONFIG[::APP_ENV || "test"][k.to_sym] = v if VALID_CONFIG_KEYS.include? k.to_sym}
      end

      # Configure through yaml file
      def self.configure_with path_to_yaml_file
        config = DEFAULT_CONFIG[::APP_ENV || "test"]
        begin
          config = YAML::load(IO.read(path_to_yaml_file))[::APP_ENV || "test"]
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

      def get_incoming_queue
        @incoming_queue ||= 

        #@incoming_queues ||= configuration["incoming_queues"].map{|key, path|
        #  #here, we're going to connect to a queue given by connections[key] with path
        #  auth = configuration['connections'][key]
        #  connection_string = "stomp://#{auth['login']}:#{auth['passcode']}@#{auth['host']}"
        #  client = OnStomp.connect(connection_string)
        #  client.subscribe(path, :ack => 'client') do |m|
        #    client.ack m
        #    puts "GOT A MESSAGE: #{m}"
        #  end
        #  {key => client}
        #}
      end

      #worker-specific methods

      #do not override this unless you know what you're doing
      def setup_worker
        die if @state == :spinning_down
        @state = :initializing
        @queue_attributes = @worker_queue = @worker_dequeue_method = nil
        begin
          @queue_attributes = self.get_worker_queue_attributes
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
          self.setup_worker
          job = dequeue_message if @worker_queue
        end
        job
      end

      def long_running?
        @@is_persistent
      end

      def spin_down
        @state = :spinning_down
        { state: :spinning_down }
      end

      def status
        {
            work_queue_size: @worker_queue.nil? ? nil : @worker_queue.respond_to?(:length) ? @worker_queue.length : -1,
            average_message_process_time: @messages_processed_results.length > 0 ?
                              @messages_processed_results.reduce(:+) / @messages_processed_results.length.to_f :
                              nil,
            total_run_time: (@state == :initializing and @messages_processed == 0) ? 0 : Time.now - @start_time,
            total_messages_processed: @messages_processed,
            state: @state
        }
      end

      def terminate
        Thread.new do
          sleep 1
          exit 0
        end
        { success: true }
      end


      protected
      def die
        exit 0
      end

      def log_results time
        @messages_processed_results << time
        @messages_processed += 1
        @messages_processed_results.slice! 1, MINIMUM_RESULTS_TO_KEEP if @messages_processed_results.length > MINIMUM_RESULTS_TO_KEEP * 2
      end

      def start_command_thread
        @command_thread = Thread.new do
          while command = STDIN.gets.chomp
            retval = nil
            command, *args = command.split(' ')
            case command.downcase
              when "status"
                retval = status
              when "spin_down"
                retval = spin_down
              when "terminate"
                retval = terminate
              when "enqueue"
                retval = enqueue_message args.join(' ')
              else
                retval = { error: "bad_input", command: command, args: args}
            end
            puts "#{retval.to_json}"
          end
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
    end
  end
end
