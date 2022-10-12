require 'gush'
require 'json'
require 'pry'

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = nil

class Prepare < Gush::Job; end
class FetchFirstJob < Gush::Job; end
class FetchSecondJob < Gush::Job; end
class PersistFirstJob < Gush::Job; end
class PersistSecondJob < Gush::Job; end
class NormalizeJob < Gush::Job; end
class BobJob < Gush::Job; end

GUSHFILE = Pathname.new(__FILE__).parent.join("Gushfile")

class TestWorkflow < Gush::Workflow
  def configure
    run Prepare

    run NormalizeJob

    run FetchFirstJob,   after: Prepare
    run FetchSecondJob,  after: Prepare, before: NormalizeJob

    run PersistFirstJob, after: FetchFirstJob, before: NormalizeJob
  end
end

class ParameterTestWorkflow < Gush::Workflow
  def configure(param)
    run Prepare if param
  end
end


REDIS_URL = ENV["REDIS_URL"] || "redis://localhost:6379/12"

module GushHelpers
  def redis
    @redis ||= Redis.new(url: REDIS_URL)
  end

  def perform_one
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.first
    if job
      Gush::Worker.new.perform(*job[:args])
      ActiveJob::Base.queue_adapter.performed_jobs << job
      ActiveJob::Base.queue_adapter.enqueued_jobs.shift
    end
  end

  def jobs_with_id(jobs_array)
    jobs_array.map {|job_name| job_with_id(job_name) }
  end

  def job_with_id(job_name)
    /#{job_name}|(?<identifier>.*)/
  end
end

RSpec::Matchers.define :have_jobs do |flow, expected_job_names|
  match do |actual|
    jobs = expected_job_names.map {|name| flow.find_job(name) }

    expected = jobs.map do |job|
      hash_including(args: [flow.id, job.id])
    end
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to match_array(expected)
  end

  failure_message do |actual|
    job_names = ActiveJob::Base.queue_adapter.enqueued_jobs.map{ |j| flow.find_job(j[:args][1]).class.name }
    "expected queue to have #{expected_job_names.join(', ')}, but instead has: #{job_names.join(', ')}"
  end
end

RSpec::Matchers.define :have_no_jobs do |flow, expected_job_names|
  match do |actual|
    jobs = expected_job_names.map {|name| flow.find_job(name) }

    expected = jobs.map do |job|
      hash_including(args: include(flow.id, job.id))
    end
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).not_to match_array(expected)
  end

  failure_message do |actual|
    job_names = ActiveJob::Base.queue_adapter.enqueued_jobs.map{ |j| flow.find_job(j[:args][1]).class.name }
    "expected queue to have no #{expected_job_names.join(', ')}, but instead has: #{job_names.join(', ')}"
  end
end

RSpec.configure do |config|
  config.include ActiveJob::TestHelper
  config.include GushHelpers

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.before(:each) do
    clear_enqueued_jobs
    clear_performed_jobs

    Gush.configure do |config|
      config.redis_url        = REDIS_URL
      config.gushfile         = GUSHFILE
      config.locking_duration = defined?(locking_duration) ? locking_duration : 50
      config.polling_interval = defined?(polling_interval) ? polling_interval : 10
    end
  end

  config.after(:each) do
    clear_enqueued_jobs
    clear_performed_jobs
    redis.flushdb
  end
end
