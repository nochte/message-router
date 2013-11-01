require 'timeout'

module Message
  module Router
    class Base
      attr_accessor :state, :worker_queue, :worker_dequeue_method

      MINIMUM_RESULTS_TO_KEEP = 20
      @@is_persistent = false

      #override this method
      #note: if a message is passed in, then the return should be
      #  the specific queue that the message is destined for
      def get_worker_queue_attributes message = nil
        {:queue => [], :dequeue => :pop, :enqueue => :push}
      end

      #override this method
      def process_job job
        raise "Not implemented yet. This is where you implement your business logic"
      end

      def initialize
        @start_time = Time.now
        @state = :initializing
        @messages_processed = 0
        @messages_processed_results = [] #we're going to hold timings in this here array
      end

      #do not override this unless you know what you're doing
      def setup
        @state = :initializing
        @queue_attributes = @worker_queue = @worker_dequeue_method = nil
        begin
          @queue_attributes = self.get_worker_queue_attributes
        end while @queue_attributes.nil?

        @worker_queue = @queue_attributes[:queue]
        @worker_dequeue_method = @queue_attributes[:dequeue]
        @state = :idle
      end

      def run
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
          self.setup
          job = dequeue_message if @worker_queue
        end
        job
      end

      def enqueue_message message
        qa = get_worker_queue_attributes message
        qa[:queue].send(qa[:enqueue], message)
      end

      def dequeue_message
        @worker_queue.send(@worker_dequeue_method)
      end

      def long_running?
        @@is_persistent
      end

      protected
      def die
        exit 0
      end

      def log_results time
        @message_processed_results << Time.now - work_time_start
        @message_processed_results.slice! 1, MINIMUM_RESULTS_TO_KEEP if @message_processed_results.length > MINIMUM_RESULTS_TO_KEEP * 2
      end
    end
  end
end
