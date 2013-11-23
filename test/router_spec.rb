require './lib/message/worker'

describe "router" do
  let(:message){ "test message" }
  let(:mock_queue_attributes) { {:queue => [], :dequeue => :pop, :enqueue => :push} }
  let(:mock_full_queue_attributes) { {:queue => (1..25).map{|x| x}, :dequeue => :pop, :enqueue => :push} }

  before :each do
    ::APP_ENV = "test"
    @router = Message::Worker::Base.new(:router => true, :worker => false)
  end

  after :each do
    Message::Worker::Base.class_eval("@@configuration = nil")
    Object.send :remove_const, :APP_ROOT if defined? ::APP_ROOT
    Object.send :remove_const, :APP_ENV if defined? ::APP_ENV
  end

  context "Routing" do
    describe ".configuration" do
      it "should lazily load the configuration" do
        @router.instance_variables.include?(:@configuration).should == false
        @router.configuration
        @router.instance_variables.include?(:@configuration).should == true
      end

      it "should have default activemq connection parameters" do
        @router.configuration['incoming_queues'].should_not be_nil
        @router.configuration['incoming_queues']['test1'].should_not be_nil
        @router.configuration['connections'].should_not be_nil
        @router.configuration['connections']['test1'].should_not be_nil
        @router.configuration['connections']['test1']['host'].should_not be_nil
        @router.configuration['connections']['test1']['login'].should_not be_nil
        @router.configuration['connections']['test1']['passcode'].should_not be_nil
      end

      it "should allow the dev to override the default config file with ::APP_ROOT" do
        ::APP_ROOT = `pwd`.chomp
        @router.configuration['incoming_queues'].should_not be_nil
        @router.configuration['incoming_queues'].keys.include?("test1").should == true
        @router.configuration['incoming_queues'].keys.include?("test2").should == true
        @router.configuration['incoming_queues'].keys.include?("test3").should == true
        @router.configuration['incoming_queues'].keys.include?("test4").should == true
        @router.configuration['connections'].should_not be_nil
        @router.configuration['connections'].keys.include?("test2").should == true
      end

      it "should allow the dev to override the default environment with ::APP_ENV" do
        ::APP_ROOT = `pwd`.chomp
        ::APP_ENV = 'test2'
        @router.configuration['incoming_queues'].should_not be_nil
        @router.configuration['incoming_queues'].keys.include?("test5").should == true
        @router.configuration['connections'].should_not be_nil
        @router.configuration['connections'].keys.include?("test5").should == true
      end

      it "should keep a persistent configuration" do
        ::APP_ROOT = `pwd`.chomp
        ::APP_ENV = 'test2'
        @router.configuration
        Object.send :remove_const, :APP_ROOT
        Object.send :remove_const, :APP_ENV
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

  end

  #process management involves spinning processes up and down automatically
  context "Process Management" do
    describe ".start_worker" do
      it "should fork a process" do
        Spawnling.should_receive(:new)
        @router.start_worker rescue nil
      end

      it "should record the worker into @workers array" do
        @router.workers.should be_nil
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

    describe ".start_monitor_thread" do
      before :each do
        Message::Worker::Base::MONITOR_THREAD_RESPAWN_TIME = 0.1
        @router.start_worker
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

      it "when killed, should restart the @monitor thread" do
        @router.send(:start_monitor_thread)
        sleep 0.2
        @router.monitor_thread.kill
        sleep 0.2
        @router.monitor_thread.alive?.should == true
      end

      it "should call status on its worker threads" do
        key = @router.workers.keys.first
        @router.workers[key][:command].should_receive(:puts).with("status")
        @router.send(:start_monitor_thread)
        sleep 1
      end

      it "should lazily load worker threads' status" do
        key = @router.workers.keys.first
        @router.workers[key][:status_history].should be_nil
        @router.send(:start_monitor_thread)
        sleep 0.2
        @router.workers[key][:status_history].should_not be_nil
      end
    end

    context "needing to change the number of workers" do
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

          it "should be true if the number of workers is < minimum_workers" do
            @router.workers.should be_nil
            @router.new_worker_needed?.should be_true
          end

          it "should be false if the number of workers is >= maximum_workers" do
            (@router.maximum_workers).times do |x|
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

          it "isn't done yet" do
            1.should == 2
          end
        end


        #it "should be true if last_worker_spawned_at is nil" do
        #
        #end
        #
        #it "should be false if last_worker_spawned_at is not long enough ago" do
        #
        #end
        #
        #it "should be false if the number of workers is greater than the maximum"
      end
    end
  end
end