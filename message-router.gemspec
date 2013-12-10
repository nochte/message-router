# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'message/router/version'

Gem::Specification.new do |spec|
  spec.name          = "message_router"
  spec.version       = Message::Router::VERSION
  spec.authors       = ["Nate Rowland"]
  spec.email         = ["nochte@gmail.com"]
  spec.description   = %q{message-router high-throughput routing of activemq messages}
  spec.summary       = %q{message-router handles high-throughput routing of messages from activemq into an
                          arbitrary shared memory data store. By default, that is redis.}
  spec.homepage      = ""
  spec.license       = "MIT"

  #files = `git ls-files`.split($/)
  files = ['lib/message_router.rb', 'lib/monkey_patches.rb', 'lib/util.rb', 'lib/message/worker.rb']
  spec.files         = files
  #spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 2.6.0"
  spec.add_dependency "onstomp", "~> 1.0.7"
end
