require 'timeout'

module Numerex
  module Message
    module Router
      class Base

      end

      class Worker
        MINIMUM_RESULTS_TO_KEEP = 20

        #override this method
        def get_worker_queue_attributes
          [[], :pop]
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

        def setup
          @state = :initializing
          begin
            Timeout::timeout(30) do
              @queue, @dequeue_method = get_worker_queue_attributes
            end
          rescue Timeout::Error => ee
            @state = :idle
            die
          end
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
          begin
            Timeout::timeout(30) do
              @queue.send(@dequeue_method)
            end
          rescue Timeout::Error => ee
            setup
            get_next_job
          end
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
end
