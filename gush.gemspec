# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'gush/version'

Gem::Specification.new do |spec|
  spec.name          = "gush"
  spec.version       = Gush::VERSION
  spec.authors       = ["Piotrek Okoński"]
  spec.email         = ["piotrek@okonski.org"]
  spec.summary       = "Fast and distributed workflow runner using only Sidekiq and Redis"
  spec.homepage      = "https://github.com/pokonski/gush"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = "gush"
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq"
  spec.add_dependency "yajl-ruby"
  spec.add_dependency "redis"
  spec.add_dependency "ruby-graphviz"
  spec.add_dependency "rubytree", "~> 0.9.3"
  spec.add_dependency "terminal-table"
  spec.add_dependency "colorize"
  spec.add_dependency "thor"
  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
