require './lib/numerex/message/router'

describe "worker" do
  before :each do
    @worker = Numerex::Message::Router::Base.new
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
    let(:message){ "test message" }
    it "should call get_worker_queue_attributes with the message as a parameter" do
      @worker.should_receive(:get_worker_queue_attributes).with(message).once.and_return({:queue => [], :dequeue => :pop, :enqueue => :push})
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

  describe ".dequeue_message" do

  end

  describe ".spin_down" do

  end

  describe ".status" do

  end

  describe ".process_job" do
    it "should respond" do
      @worker.respond_to?(:process_job).should == true
    end
  end

  describe ".long_running?" do
    it "should respond publicly" do
      @worker.respond_to?(:long_running?).should == true
      @worker.long_running?.should == false
    end
  end
end