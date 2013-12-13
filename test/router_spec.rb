require './lib/message_router'

describe "router" do
  let(:message){ "test message" }
  let(:mock_queue_attributes) { {:queue => [], :dequeue => :pop, :enqueue => :push} }
  let(:mock_full_queue_attributes) { {:queue => (1..25).map{|x| x}, :dequeue => :pop, :enqueue => :push} }

  before :each do
    ENV['APP_ENV'] = "test"
    @router = Message::Worker::Base.new(:router => false, :worker => false) #setting to false to keep threads from starting
  end

  after :each do
    Message::Worker::Base.class_eval("@@configuration = nil")
    ENV['APP_ENV'] = nil
    ENV['APP_ROOT'] = nil
    #Object.send :remove_const, :APP_ROOT if defined? ENV['APP_ROOT']
    #Object.send :remove_const, :APP_ENV if defined? ENV['APP_ENV']
  end

  context "Routing" do
    describe ".configuration" do
      before :each do
        ENV['APP_ROOT'] = nil
      end
      after :each do
        ENV['APP_ROOT'] = nil
      end

      it "should lazily load the configuration" do
        @router.instance_variables.include?(:@configuration).should == false
        @router.configuration
        @router.instance_variables.include?(:@configuration).should == true
      end

      #it "should have default activemq connection parameters" do
      #  @router.configuration['incoming_queues'].should_not be_nil
      #  @router.configuration['incoming_queues']['test1'].should_not be_nil
      #  @router.configuration['connections'].should_not be_nil
      #  @router.configuration['connections']['test1'].should_not be_nil
      #  @router.configuration['connections']['test1']['host'].should_not be_nil
      #  @router.configuration['connections']['test1']['login'].should_not be_nil
      #  @router.configuration['connections']['test1']['passcode'].should_not be_nil
      #end

      it "should allow the dev to override the default config file with ENV['APP_ROOT']" do
        ENV['APP_ROOT'] = `pwd`.chomp
        @router.configuration['incoming_queues'].should_not be_nil
        @router.configuration['incoming_queues'].keys.include?("test1").should == true
        @router.configuration['incoming_queues'].keys.include?("test2").should == true
        @router.configuration['incoming_queues'].keys.include?("test3").should == true
        @router.configuration['incoming_queues'].keys.include?("test4").should == true
        @router.configuration['connections'].should_not be_nil
        @router.configuration['connections'].keys.include?("test2").should == true
      end

      it "should allow the dev to override the default environment with ENV['APP_ENV']" do
        ENV['APP_ROOT'] = `pwd`.chomp
        ENV['APP_ENV'] = 'test2'
        @router.configuration['incoming_queues'].should_not be_nil
        @router.configuration['incoming_queues'].keys.include?("test5").should == true
        @router.configuration['connections'].should_not be_nil
        @router.configuration['connections'].keys.include?("test5").should == true
      end

      it "should keep a persistent configuration" do
        ENV['APP_ROOT'] = `pwd`.chomp
        ENV['APP_ENV'] = 'test2'
        @router.configuration
        @router.configuration['incoming_queues'].should_not be_nil
        @router.configuration['incoming_queues'].keys.include?("test5").should == true
        @router.configuration['connections'].should_not be_nil
        @router.configuration['connections'].keys.include?("test5").should == true
      end
    end

    describe ".incoming_queue" do
      it "should lazily connect to the configured queue" do
        @router.instance_variables.include?(:@incoming_queue).should == false
        @router.incoming_queue
        @router.instance_variables.include?(:@incoming_queue).should == true
      end

      it "should keep a persistent connection" do
        q1 = @router.incoming_queue
        q2 = @router.incoming_queue
        q1.should == q2
      end

      it "should subscribe the the configured queue" do
        configuration = @router.configuration
        incoming_queue = configuration['incoming_queues'].keys.first
        auth = configuration['connections'][incoming_queue]
        connection_string = "stomp://#{auth['login']}:#{auth['passcode']}@#{auth['host']}"
        client = OnStomp.connect(connection_string)
        OnStomp.stub(:connect).and_return(client)
        client.should_receive(:subscribe)
        @router.incoming_queue
      end
    end

    describe ".on_incoming_message" do
      let(:message) {'{"hi":"there"}'}
      it "should parse the message" do
        JSON.should_receive(:parse)
        @router.on_incoming_message(message)
      end

      it "should call enqueue_message" do
        @router.should_receive(:enqueue_message)
        @router.on_incoming_message(message)
      end

      it "should write malformed messages to the log" do
        @router.should_receive(:log)
        @router.on_incoming_message("bad message")
      end
    end
  end

  #c&c involves calling on the router to get stats, manually spin up or down workers
  context "Command and Control" do
    before :each do
      @router = Message::Worker::Base.new({router: true, worker: false})
    end

    describe "initialize" do
      it "should start_command_thread on initialization" do
        @router.instance_variables.include?(:@command_thread).should == true
      end
      it "should @command_pipe to STDIN" do
        @router.instance_variable_get(:@command_pipe).should == STDIN
      end
      it "should set @status_pipe to STDOUT" do
        @router.instance_variable_get(:@status_pipe).should == STDOUT
      end
    end

    describe "command_thread" do
      it "should accept spawn_worker" do
        result = @router.send(:process_command, "spawn_worker", nil)
        result[:success].should == true
      end

      it "should accept kill_worker" do
        @router.start_worker
        sleep 1
        result = @router.send(:process_command, "kill_worker", @router.workers.keys.first)
        result[:success].should == true
      end

      it "should accept worker_pids" do
        @router.start_worker
        sleep 1
        result = @router.send(:process_command, "worker_pids", nil)
        result[:workers].include?(@router.workers.keys.first)
      end

      it "should accept worker_status" do
        @router.start_worker
        sleep 1
        @router.should_receive(:worker_status)
        result = @router.send(:process_command, "status", nil)
        result[:ok].should == true
        result[:average_work_queue_size].should_not be_nil
      end

      it "should accept worker_status with a parameter" do
        @router.start_worker
        sleep 1
        key = @router.workers.keys.first
        result = @router.send(:process_command, "status", key)
        result[:ok].should == true
        worker[:pid].should == key
      end
    end
  end

  #process management involves spinning processes up and down automatically
  context "Process Management" do
    describe ".start_worker" do
      it "should fork a process" do
        Spawnling.should_receive(:new)
        @router.start_worker rescue nil
      end

      it "should record the worker into @workers array" do
        @router.workers.should == {}
        @router.start_worker
        sleep 0.1
        @router.workers.class.should == Hash
        key = @router.workers.keys.first
        @router.workers[key][:process_name].should == "Message::Worker::Base - 0"
      end

      it "should capture the IO ports for the spawned worker" do
        @router.start_worker
        key = @router.workers.keys.first
        worker = @router.workers[key]
        worker[:command].should_not be_nil
        worker[:status].should_not be_nil
        worker[:process].class.should == Spawnling
      end

      it "should set the last worker spawn time to new" do
        @router.last_worker_spawned_at.should == nil
        @router.start_worker
        (@router.last_worker_spawned_at > Time.now - 60).should be_true
      end
    end

    describe ".start_monitor_service_thread" do
      before :each do
        @monitor_thread = {}
        @monitor_thread.stub(:alive?).and_return(:true)
        @router.stub(:start_monitor_thread).and_return(@monitor_thread)
      end

      after :each do
        @router.unstub(:start_monitor_thread)
      end

      it "should set @monitor_service_thread" do
        @router.instance_variables.include?(:@monitor_service_thread).should == false
        @router.send :start_monitor_service_thread
        @router.instance_variables.include?(:@monitor_service_thread).should == true
        sleep 1
      end

      it "should call .start_monitor_thread" do
        @router.should_receive(:start_monitor_thread)
        @router.send :start_monitor_service_thread
        sleep 1
      end

      context "with a dead monitor thread" do
        before :each do
          @monitor_thread.stub(:alive?).and_return(false)
          Message::Worker::Base::MONITOR_THREAD_RESPAWN_TIME = 0.025
        end

        after :each do
          @monitor_thread.stub(:alive?).and_return(true)
        end

        it "should call .start_monitor_thread again" do
          @router.should_receive(:start_monitor_thread).at_least(2)
          @router.send :start_monitor_service_thread
          sleep 1
        end
      end
    end

    describe '.fetch_status!' do
      context "given a bad worker" do
        it "should throw an exception" do
          expect {@router.send(:fetch_status!, {})}.to raise_error("Worker Unreachable")
        end
      end

      context "given a good worker" do
        before :each do
          @history_item = {
              work_queue_size: 0,
              average_message_process_time: 0,
              total_run_time: 0,
              total_messages_processed: 0,
              state: :idle,
              timestamp: Time.now,
              idle_time: 0,
              idle_time_percentage: 100.0
          }
          @router.class.stub(:command_worker).and_return(@history_item)
          @worker = {}
        end

        after :each do
          @router.class.unstub(:command_worker)
        end

        it "should call command_worker with the worker and 'status'" do
          @router.class.should_receive(:command_worker).with(@worker, 'status')
          @router.send(:fetch_status!, @worker)
        end

        it "should create a status_history array" do
          @worker[:status_history].should be_nil
          @router.send(:fetch_status!, @worker)
          @worker[:status_history].class.should == Array
          @worker[:status_history].length.should == 1
        end

        it "should add the returned history to the status_history array" do
          @router.send(:fetch_status!, @worker)
          @worker[:status_history].first.should == @history_item
        end

        context "with an over-full status_history array" do
          before :each do
            (Message::Worker::Base::MINIMUM_STATUS_METRICS_TO_KEEP * 3).times do |i|
              (@worker[:status_history] ||= []) << {
                  work_queue_size: i,
                  average_message_process_time: 0,
                  total_run_time: 0,
                  total_messages_processed: 0,
                  state: :idle,
                  timestamp: Time.now,
                  idle_time: 0,
                  idle_time_percentage: 100.0
              }
            end

          end

          it "should remove history_items down to MINIMUM_STATUS_METRICS_TO_KEEP" do
            @worker[:status_history].length.should == Message::Worker::Base::MINIMUM_STATUS_METRICS_TO_KEEP * 3
            @router.send(:fetch_status!, @worker)
            @worker[:status_history].length.should == Message::Worker::Base::MINIMUM_STATUS_METRICS_TO_KEEP
          end
        end
      end
    end

    describe ".start_monitor_thread" do
      let(:start_worker){true}
      before :each do
        Message::Worker::Base::MONITOR_THREAD_RESPAWN_TIME = 0.1
        @router.start_worker if start_worker
      end

      after :each do
        Message::Worker::Base::MONITOR_THREAD_RESPAWN_TIME = 1
      end

      it "should not be public" do
        @router.respond_to?(:start_monitor_thread).should == true
        expect { @router.start_monitor_thread }.to raise_error
      end

      it "should set @monitor_thread to be a thread" do
        @router.send(:start_monitor_thread)
        sleep 0.2
        @router.monitor_thread.class.should == Thread
      end

      it "should call status on its worker threads" do
        worker = @router.workers.first[1]
        @router.should_receive(:fetch_status!).with(worker)
        @router.send(:start_monitor_thread)
        sleep 1
      end

      context "with insufficient workers for the job" do
        before :each do
          @router.stub(:new_worker_needed?).and_return(true)
        end
        after :each do
          @router.unstub(:new_worker_needed?)
        end

        it "should scale up" do
          @router.should_receive(:start_worker)
          @router.send(:start_monitor_thread)
          sleep 1
        end
      end

      context "with a dead worker" do
        let(:start_worker){false}
        let(:worker){
          {
              12345 => {
                  :command => "Mock IO Pipe",
                  :status => "Mock IO Pipe",
                  :process => "Mock Spawnling Object",
                  :process_name => "Mock Process Name",
                  :status_history => []
              }
          }
        }
        before :each do
          @router.stub(:fetch_status!){raise Message::Worker::DeadWorkerException.new("Stubbed")}
          @router.register_worker(worker.keys.first, worker.values.first)
        end

        it "should clean up that worker's mess" do
          @router.should_receive(:clean_worker!).with(worker.keys.first)
          @router.send(:start_monitor_thread)
          sleep 1
        end
      end

      context "the worker_status hash" do
        before :each do
          @router.stub(:minimum_workers).and_return(0)
          @router.stub(:new_worker_needed?).and_return(false)
          @router.send(:start_monitor_thread)
          sleep 0.2
        end

        after :each do
          @router.unstub(:minimum_workers)
          @router.unstub(:new_worker_needed?)
        end

        it "should have some properties" do
          @router.respond_to?(:worker_status).should == true
          @router.worker_status.class.should == Hash
          status = @router.worker_status
          status.key?(:average_work_queue_size).should == true
          status.key?(:average_message_process_time).should == true
          status.key?(:average_total_run_time).should == true
          status.key?(:average_messages_processed).should == true
          status.key?(:average_idle_time).should == true
          status.key?(:average_idle_time_percentage).should == true
        end

        context "with no workers" do
          let(:start_worker){false}
          it "properties should all be 0" do
            status = @router.worker_status
            status[:average_work_queue_size].should == 0
            status[:average_message_process_time].should == 0
            status[:average_total_run_time].should == 0
            status[:average_messages_processed].should == 0
          end
        end

        context "with some workers" do
          before :each do
            @router.start_worker
            keys = [@router.workers.keys.first, @router.workers.keys.last]
            @router.workers[keys.first][:status_history] = [{
                'work_queue_size' =>  1,
                'average_message_process_time' =>  3,
                'total_run_time' =>  60,
                'total_messages_processed' =>  5,
                'state' =>  :idle,
                'timestamp' =>  Time.now - 2
            }]

            @router.workers[keys.last][:status_history] = [{
                'work_queue_size' =>  5,
                'average_message_process_time' =>  10,
                'total_run_time' =>  30,
                'total_messages_processed' =>  10,
                'state' =>  :idle,
                'timestamp' =>  Time.now - 1
            }]
          end

          it "should have floats" do
            status = @router.worker_status
            status[:average_work_queue_size].should == 3.0
            status[:average_message_process_time].should == 13.0/2.0
            status[:average_total_run_time].should == 45
            status[:average_messages_processed].should == 7.5
          end
        end
      end
    end

    context "needing to change the number of workers" do
      describe ".clean_worker!" do
        let(:worker){
          {
              12345 => {
              :command => "Mock IO Pipe",
              :status => "Mock IO Pipe",
              :process => "Mock Spawnling Object",
              :process_name => "Mock Process Name",
              :status_history => []
            }
          }
        }

        before :each do
          @router.workers[worker.keys.first] = worker.values.first
        end

        it "should kill the worker's process by PID" do
          Process.should_receive(:kill).with("TERM", worker.keys.first)
          @router.send(:clean_worker!, worker.keys.first)
        end

        it "should remove the worker from the @workers hash" do
          @router.workers.length.should == 1
          @router.send(:clean_worker!, worker.keys.first)
          @router.workers.length.should == 0
        end
      end

      describe ".new_worker_needed?" do
        context "last_worker_spawned_at is nil" do
          before :each do
            @router.stub(:last_worker_spawned_at).and_return(nil)
          end
          after :each do
            @router.unstub(:last_worker_spawned_at)
          end

          it "should be true" do
            @router.new_worker_needed?.should be_true
          end
        end

        context "last_worker_spawned_at is not long enough ago" do
          before :each do
            @router.stub(:last_worker_spawned_at).and_return(Time.now - 1)
          end
          after :each do
            @router.unstub(:last_worker_spawned_at)
          end

          context "number of workers is < minimum_workers" do
            before :each do
              worker_stub = {}
              @router.stub(:workers).and_return(worker_stub)
            end

            after :each do
              @router.unstub(:workers)
            end

            it "should be true" do
              @router.new_worker_needed?.should be_true
            end
          end

          context "number of workers is >= minimum_workers" do
            before :each do
              worker_stub = {}
              (@router.minimum_workers).times do |x|
                worker_stub[x] = "blah"
              end
              @router.stub(:workers).and_return(worker_stub)
            end

            after :each do
              @router.unstub(:workers)
            end
            it "should be false" do
              @router.new_worker_needed?.should be_false
            end
          end

          it "should be false if the number of workers is >= minimum_workers" do
            (@router.minimum_workers).times do |x|
              @router.register_worker x, {}
            end
            @router.new_worker_needed?.should be_false
          end

        end

        context "last_worker_spawned_at is a long time ago" do
          before :each do
            @router.stub(:last_worker_spawned_at).and_return(Time.now - 60*60*24) #a full day ago
          end
          after :each do
            @router.unstub(:last_worker_spawned_at)
          end

          context "number of workers is < minimum_workers" do
            before :each do
              worker_stub = {}
              (@router.minimum_workers - 1).times do |x|
                worker_stub[x] = "blah"
              end
              @router.stub(:workers).and_return(worker_stub)
            end

            after :each do
              @router.unstub(:workers)
            end

            it "should be true" do
              @router.new_worker_needed?.should == true
            end
          end

          context "number of workers is >= maximum_workers" do
            before :each do
              worker_stub = {}
              (@router.maximum_workers + 1).times do |x|
                worker_stub[x] = "blah"
              end
              @router.stub(:workers).and_return(worker_stub)
            end

            after :each do
              @router.unstub(:workers)
            end

            it "should be false" do
              @router.new_worker_needed?.should == false
            end
          end

          context "the number of workers is >= minimum_workers and < maximum_workers" do
            let(:average_idle_time_percentage){50.0}
            before :each do
              worker_stub = {}
              (@router.maximum_workers - 1).times do |x|
                worker_stub[x] = "blah"
              end
              @router.stub(:workers).and_return(worker_stub)
              @router.stub(:worker_status).and_return({
                                                         average_work_queue_size: 0,
                                                         average_message_process_time: 0,
                                                         average_total_run_time: 0,
                                                         average_messages_processed: 0,
                                                         average_idle_time: 0,
                                                         average_idle_time_percentage: average_idle_time_percentage
                                                     })
            end

            after :each do
              @router.unstub(:worker_status)
            end

            context "average_idle_time_percentage < 30%" do
              let(:average_idle_time_percentage){20}

              it "should be true" do
                @router.new_worker_needed?.should == true
              end
            end

            context "average_idle_time_percentage > 30%" do
              let(:average_idle_time_percentage){50}

              it "should be false" do
                @router.new_worker_needed?.should == false
              end
            end
          end
        end
      end
    end
  end
end