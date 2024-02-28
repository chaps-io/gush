# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require_relative 'lib/gush/version'

Gem::Specification.new do |spec|
  spec.name          = "gush"
  spec.version       = Gush::VERSION
  spec.authors       = ["Piotrek Okoński"]
  spec.email         = ["piotrek@okonski.org"]
  spec.summary       = "Fast and distributed workflow runner based on ActiveJob and Redis"
  spec.description   = "Gush is a parallel workflow runner using Redis as storage and ActiveJob for executing jobs."
  spec.homepage      = "https://github.com/chaps-io/gush"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = "gush"
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.required_ruby_version = '>= 3.0.0'

  spec.add_dependency "activejob", ">= 6.1.0", "< 7.2"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "multi_json", "~> 1.11"
  spec.add_dependency "redis", ">= 3.2", "< 6"
  spec.add_dependency "redis-mutex", "~> 4.0.1"
  spec.add_dependency "hiredis", "~> 0.6"
  spec.add_dependency "graphviz", "~> 1.2"
  spec.add_dependency "terminal-table", ">= 1.4", "< 3.1"
  spec.add_dependency "paint", "~> 2.2"
  spec.add_dependency "thor", ">= 0.19", "< 1.3"
  spec.add_dependency "launchy", "~> 2.4"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 12"
  spec.add_development_dependency "rspec", '~> 3.0'
  spec.add_development_dependency "pry", '~> 0.10'
end
