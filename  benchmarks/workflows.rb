require 'benchmark/ips'
require 'gush'
require_relative './config'

Benchmark.ips do |x|
  x.config(time: 30, warmup: 3)

  x.report("BigWorkflow") do
    flow = BigWorkflow.create
    flow.start!
  end
end
