require 'active_support'
require 'active_support/testing/time_helpers'
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
  def configure(param, kwarg: false)
    run Prepare if param || kwarg
  end
end

class WaitableTestWorkflow < Gush::Workflow
  def configure
    run Prepare, wait: 5.minutes
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

RSpec::Matchers.define :have_jobs do |flow, jobs|
  match do |actual|
    expected = jobs.map do |job|
      hash_including(args: include(flow, job))
    end
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to match_array(expected)
  end

  failure_message do |actual|
    "expected queue to have #{jobs}, but instead has: #{ActiveJob::Base.queue_adapter.enqueued_jobs.map{ |j| j[:args][1]}}"
  end
end

RSpec::Matchers.define :have_no_jobs do |flow, jobs|
  match do |actual|
    expected = jobs.map do |job|
      hash_including(args: include(flow, job))
    end
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).not_to match_array(expected)
  end

  failure_message do |actual|
    "expected queue to have no #{jobs}, but instead has: #{ActiveJob::Base.queue_adapter.enqueued_jobs.map{ |j| j[:args][1]}}"
  end
end

RSpec::Matchers.define :have_a_job_enqueued_at do |flow, job, at|
  expected_execution_timestamp = (Time.current.utc + at).to_i

  match do |actual|
    expected = hash_including(args: include(flow, job), at: expected_execution_timestamp)

    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to match_array(expected)
  end

  failure_message do |actual|
    "expected to have enqueued job #{job} to be executed at #{Time.current.utc + at}, but instead has: #{Time.at(enqueued_jobs.first[:at]).to_datetime.utc}"
  end
end

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
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
      config.locking_duration = defined?(locking_duration) ? locking_duration : 2
      config.polling_interval = defined?(polling_interval) ? polling_interval : 0.3
    end
  end

  config.after(:each) do
    clear_enqueued_jobs
    clear_performed_jobs
    redis.flushdb
  end
end
