require './lib/util'
include Util

describe "util" do
  describe "summarize_history" do
    describe "with numeric values" do
      let(:history){
        [
            {
                key1: 2.25,
                key2: 3.9,
                "key3" => 19.7
            },
            {
                key1: 6.3,
                key2: 4.2,
                "key3" => 6
            },
            {
                key1: 1,
                key2: 17,
                "key3" => 2.25
            }
        ]
      }

      it "should average the input keys" do
        summarize_history(history)[:key1].round(3).should == ((2.25+1+6.3)/3).round(3)
        summarize_history(history)[:key2].round(3).should == ((3.9+17+4.2)/3).round(3)
        summarize_history(history)["key3"].round(3).should == ((19.7+2.25+6)/3).round(3)
      end
    end

    describe "with non-numeric values" do
      let(:history) {
        [
            {
                "key1" => "some text here",
                "key2" => "other text here"
            },
            {
                "key1" => "some text here 2",
                "key2" => "other text here 2"
            }
        ]
      }
      it "should not include keys with non-numeric values" do
        summarize_history(history).key?("key1").should == false
        summarize_history(history).key?("key2").should == false
      end
    end

    describe "with a mix of numeric values and non-numeric values" do
      let(:history){
        [
            {
                "key1" => "some text here",
                "key2" => "other text here",
                key3: 3.25
            },
            {
                "key1" => "some text here 2",
                "key2" => "other text here 2",
                key3: 9.8
            }
        ]
      }

      it "should not include keys with non-numeric values" do
        summarize_history(history).key?("key1").should == false
        summarize_history(history).key?("key2").should == false
      end

      it "should include keys with numeric values" do
        summarize_history(history).key?(:key3).should == true
      end
    end

    describe "with non-matching keys" do
      let(:history){
        [
            {
                key1: 2.25,
                key2: 3.9,
            },
            {
                key2: 17,
                "key3" => -3.9
            }
        ]
      }

      it "should average existing keys for all items" do
        summarize_history(history)[:key1].round(3).should == 2.25.round(3)
        summarize_history(history)[:key2].round(3).should == (17.0+3.9)/2.round(3)
        summarize_history(history)["key3"].round(3).should == -3.9.round(3)
      end
    end
  end
end
