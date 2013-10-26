require './lib/numerex/message/router'

describe "worker" do
  before :each do
    @worker = Numerex::Message::Router::Worker.new
  end

  describe "get_worker_queue_attributes" do
    it "should have a get_worker_queue_attributes" do
      @worker.respond_to?(:get_worker_queue_attributes).should == true
    end

    it "should return an array with an object and a method" do
      @worker.get_worker_queue_attributes[0].class.should_not == Symbol
      @worker.get_worker_queue_attributes[1].class.should == Symbol
    end

    it "returned object should respond to the returned method" do
      queue, method = @worker.get_worker_queue_attributes
      queue.respond_to?(method).should == true
    end
  end
end