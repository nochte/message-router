#!/usr/bin/env ruby

require "./lib/message/router/version"
require "./lib/router"

#here, we're going to read a config file to determine
#  things like what worker class (a symbol) to load

router = Message::Worker::Base.new({ :router => true })
while 1
  sleep 1
end