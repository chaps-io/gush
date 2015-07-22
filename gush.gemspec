# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "gush"
  spec.version       = "0.1.2"
  spec.authors       = ["Piotrek Okoński"]
  spec.email         = ["piotrek@okonski.org"]
  spec.summary       = "Fast and distributed workflow runner using only Sidekiq and Redis"
  spec.homepage      = "https://github.com/pokonski/gush"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = "gush"
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", "~> 3.3.4"
  spec.add_dependency "yajl-ruby", "~> 1.2.1"
  spec.add_dependency "redis", "~> 3.2.1"
  spec.add_dependency "hiredis", "~> 0.6.0"
  spec.add_dependency "ruby-graphviz", "~> 1.2.2"
  spec.add_dependency "terminal-table", "~> 1.4.5"
  spec.add_dependency "colorize", "~> 0.7.7"
  spec.add_dependency "thor", "~> 0.19.1"
  spec.add_dependency "launchy", "~> 2.4.3"
  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", '~> 3.0.0'
end
