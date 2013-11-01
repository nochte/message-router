require './lib/message/worker'

describe "worker" do
  let(:message){ "test message" }
  let(:mock_queue_attributes) { {:queue => [], :dequeue => :pop, :enqueue => :push} }
  let(:mock_full_queue_attributes) { {:queue => (1..25).map{|x| x}, :dequeue => :pop, :enqueue => :push} }

  before :each do
    @worker = Message::Worker::Base.new
  end

  describe "get_worker_queue_attributes" do
    it "should have a get_worker_queue_attributes" do
      @worker.respond_to?(:get_worker_queue_attributes).should == true
    end

    it "should return an array with an object and a method" do
      @worker.get_worker_queue_attributes[:queue].class.should_not == Symbol
      @worker.get_worker_queue_attributes[:dequeue].class.should == Symbol
      @worker.get_worker_queue_attributes[:enqueue].class.should == Symbol
    end

    it "returned object should respond to the returned method" do
      queue_attributes = @worker.get_worker_queue_attributes
      queue_attributes[:queue].respond_to?(queue_attributes[:enqueue]).should == true
      queue_attributes[:queue].respond_to?(queue_attributes[:dequeue]).should == true
    end

    it "should take an optional message parameter" do
      expect { @worker.get_worker_queue_attributes "message" }.to_not raise_error
      expect { @worker.get_worker_queue_attributes "message", "bad param" }.to raise_error
    end
  end

  describe ".enqueue_message" do
    it "should call get_worker_queue_attributes with the message as a parameter" do
      @worker.should_receive(:get_worker_queue_attributes).with(message).once.and_return(mock_queue_attributes)
      @worker.enqueue_message message
    end

    it "should call the worker_queue_attribute's enqueue method with the message as a parameter" do
      worker_queue_attributes = @worker.get_worker_queue_attributes message
      @worker.stub(:get_worker_queue_attributes).and_return worker_queue_attributes
      worker_queue_attributes[:queue].should_receive(worker_queue_attributes[:enqueue]).with(message).once
      @worker.enqueue_message message
    end

    it "should return queue on success" do
      worker_queue_attributes = @worker.get_worker_queue_attributes message
      @worker.stub(:get_worker_queue_attributes).and_return worker_queue_attributes
      @worker.enqueue_message(message).should == [message]
    end

    it "should raise an exception on failure" do
      worker_queue_attributes = @worker.get_worker_queue_attributes message
      worker_queue_attributes[:queue].stub(worker_queue_attributes[:enqueue]) { raise "error" }
      @worker.stub(:get_worker_queue_attributes).and_return worker_queue_attributes
      expect { @worker.enqueue_message(message) }.to raise_error
    end
  end

  describe ".setup" do
    let(:backlog_work_queues){[mock_queue_attributes, nil, nil, nil]}
    it "should call get_worker_queue_attributes" do
      @worker.should_receive(:get_worker_queue_attributes).once.and_return(mock_queue_attributes)
      @worker.setup
    end

    it "should set its state to :initializing while it is running" do
      t = Thread.new do
        sleep 0.1
        @worker.state.should == :initializing
      end
      @worker.stub(:get_worker_queue_attributes){sleep 1; mock_queue_attributes}
      @worker.send(:state=, :null)
      @worker.setup
      t.join
    end

    it "should set its state to :idle when complete" do
      @worker.setup
      @worker.state.should == :idle
    end

    it "should set a @worker_queue" do
      @worker.worker_queue.should be_nil
      @worker.setup
      @worker.worker_queue.should_not be_nil
    end

    it "should set a @dequeue" do
      @worker.worker_dequeue_method.should be_nil
      @worker.setup
      @worker.worker_dequeue_method.should == :pop
    end

    it "should loop until it finds a queue, if one is available" do
      @worker.stub(:get_worker_queue_attributes){backlog_work_queues.pop}
      @worker.setup
      @worker.worker_queue.should == mock_queue_attributes[:queue]
    end
  end

  describe ".dequeue_message" do
    it "should throw an exception if no @work_queue is defined" do
      @worker.worker_queue.should be_nil
      expect { @worker.dequeue_message }.to raise_error
    end

    it "should throw an exception if no @dequeue is defined" do
      @worker.stub(:worker_queue){[]}
      expect { @worker.dequeue_message }.to raise_error
    end

    it "should call @worker_dequeue_method on @worker_queue" do
      @worker.stub(:get_worker_queue_attributes){mock_queue_attributes}
      @worker.setup
      mock_queue_attributes[:queue].should_receive(mock_queue_attributes[:dequeue])
      @worker.dequeue_message
    end

    context "with a @work_queue with elements in it" do
      let(:mock_queue_attributes){ { :queue => [1], :dequeue => :pop, :enqueue => :push } }
      before :each do
        @worker.stub(:get_worker_queue_attributes){mock_queue_attributes}
        @worker.setup
      end

      it "should return the element in the worker_queue" do
        @worker.dequeue_message.should == 1
      end

      it "should remove the element from the worker_queue" do
        @worker.dequeue_message
        @worker.worker_queue.length.should == 0
      end
    end

    context "with an empty @work_queue" do
      let(:mock_queue_attributes){ { :queue => [], :dequeue => :pop, :enqueue => :push } }
      before :each do
        @worker.stub(:get_worker_queue_attributes){mock_queue_attributes}
        @worker.setup
      end

      it "should return nil" do
        @worker.dequeue_message.should == nil
      end
    end
  end

  describe ".get_next_job" do
    let(:backlog_work_queues){[mock_queue_attributes, mock_queue_attributes]}
    before :each do
      @worker.worker_queue = []
      @worker.worker_dequeue_method = :pop
      @worker.stub(:get_worker_queue_attributes){ backlog_work_queues.pop }
    end

    context "with an empty work_queue" do
      context "with no further work_queues" do
        let(:backlog_work_queues){[]}

        it "should call setup" do
          @worker.should_receive(:setup).at_least(1)
          t = Thread.new do
            Timeout::timeout(1) do
              @worker.get_next_job
            end rescue nil
          end
          t.join
        end

        it "should have an :initializing state" do
          t = Thread.new do
            Timeout::timeout(1) do
              @worker.get_next_job
            end rescue nil
          end
          sleep 0.01
          @worker.state.should == :initializing
          t.join
        end
      end

      context "with another work_queue" do
        let(:mock_queue_attributes){ { :queue => [1], :dequeue => :pop, :enqueue => :push } }

        it "should grab the next queue from the queue pool" do
          backlog_work_queues.should_receive(:pop).exactly(1).and_return(mock_queue_attributes)
          t = Thread.new do
            Timeout::timeout(1) do
              @worker.get_next_job
            end rescue nil
          end
          t.join
        end
      end
    end

    context "with a work_queue with items in it" do
      let(:mock_queue_attributes){ { :queue => [1], :enqueue => :push, :dequeue => :pop } }
    end
  end

  describe ".spin_down" do
    it "should set state to :spinning_down" do
      @worker.spin_down
      @worker.state.should == :spinning_down
    end

    it "should call die instead of claiming another job" do
      @worker.should_receive(:die).exactly(1)
      @worker.spin_down
      @worker.setup
    end
  end

  describe ".status" do
    context "without being initialized" do
      it "should have a set of values, returned as a hash, set t" do
        status = @worker.status
        {   work_queue_size: nil, average_message_process_time: nil,
            total_run_time: 0, total_messages_processed: 0,
            state: :initializing}.each do |key, expected_value|
              expected_value.is_a?(Numeric) ? status[key].to_i.should == expected_value.to_i : status[key].should == expected_value
        end
      end
    end

    context "after setup, while idle" do
      it "should have a set of values, returned as a hash" do
        @worker.stub(:get_worker_queue_attributes).and_return mock_queue_attributes
        @worker.setup
        status = @worker.status
        {   work_queue_size: 0, average_message_process_time: nil,
            total_run_time: 0, total_messages_processed: 0,
            state: :idle}.each do |key, expected_value|
              expected_value.is_a?(Numeric) ? status[key].to_i.should == expected_value.to_i : status[key].should == expected_value
        end
      end
    end

    context "after setup, during work" do
      it "should have a set of values, returned as a hash" do
        original_queue_length = mock_full_queue_attributes[:queue].length
        @worker.stub(:get_worker_queue_attributes).and_return mock_full_queue_attributes
        @worker.setup
        @worker.stub(:process_job){sleep 0.1}
        t = Thread.new do
          Timeout::timeout 1 do
            @worker.run
          end rescue nil
        end
        sleep 0.3
        status = @worker.status
        status[:work_queue_size].should < original_queue_length
        status[:total_run_time].should > 0
        status[:total_messages_processed].should > 0
        status[:state].should == :working
        t.join
      end
    end
  end

  describe ".process_job" do
    it "should respond" do
      @worker.respond_to?(:process_job).should == true
    end

    it "should throw an exception when process_job is called" do
      expect {@worker.process_job}.to raise_error
    end
  end

  describe ".long_running?" do
    it "should respond publicly" do
      @worker.respond_to?(:long_running?).should == true
      @worker.long_running?.should == false
    end
  end
end