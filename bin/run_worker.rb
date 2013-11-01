require "./lib/message/router/version"
require "./lib/message/router"

#here, we're going to read a config file to determine
#  things like what worker class (a symbol) to load

worker = Message::Router::Worker.new
worker.setup
worker.run