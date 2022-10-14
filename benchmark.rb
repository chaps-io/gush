require "pathname"
require "bundler"
require "pry"
Bundler.require

bin_file = Pathname.new(__FILE__).realpath
# add self to libpath
$:.unshift File.expand_path("../../lib", bin_file)

require 'benchmark/ips'
require 'gush'

class Prepare < Gush::Job; end
class FetchFirstJob < Gush::Job; end
class FetchSecondJob < Gush::Job; end
class PersistFirstJob < Gush::Job; end
class PersistSecondJob < Gush::Job; end
class NormalizeJob < Gush::Job; end

class TestWorkflow < Gush::Workflow
  def configure
    run Prepare

    run NormalizeJob, after: PersistSecondJob

    run FetchFirstJob,   after: Prepare
    run FetchSecondJob,  after: Prepare

    run PersistFirstJob, after: FetchFirstJob, before: NormalizeJob
    run PersistSecondJob, after: FetchSecondJob
  end
end

Benchmark.ips do |x|
  # Configure the number of seconds used during
  # the warmup phase (default 2) and calculation phase (default 5)
  x.config(:time => 5, :warmup => 2)

  # These parameters can also be configured this way
  x.time = 5
  x.warmup = 2


  x.report("creation") do
    TestWorkflow.create
  end
end