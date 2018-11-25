require 'benchmark/ips'
require 'gush'
require 'stackprof'
require 'pry'

require_relative './config'

Benchmark.ips do |x|
  x.config(time: 60, warmup: 3)

  x.report("BigWorkflow") do
    $small_jobs = 0
    $final_jobs = 0

    flow = BigWorkflow.create
    flow.start!

    #puts "small jobs #{$small_jobs}"
    #puts "final jobs #{$final_jobs}"
  end
end

# flow = BigWorkflow.create

# StackProf.run(mode: :wall, out: 'tmp/stackprof-cpu-myapp.dump') do
#   flow.start!
# end

#StackProf::Report.new(result).print_text