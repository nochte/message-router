require "./lib/message/router/version"
require "./lib/message/worker"

#here, we're going to read a config file to determine
#  things like what worker class (a symbol) to load

worker = Message::Worker::Worker.new
worker.setup
worker.run