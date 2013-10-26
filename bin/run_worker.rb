require "./lib/numerex/message/router/version"
require "./lib/numerex/message/router"

#here, we're going to read a config file to determine
#  things like what worker class (a symbol) to load

worker = Numerex::Message::Router::Worker.new
worker.setup
worker.run