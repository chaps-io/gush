require 'gush'
require 'pry'
require 'sidekiq/testing'

Sidekiq::Testing.fake!
Sidekiq::Logging.logger = nil

class Prepare < Gush::Job; end
class FetchFirstJob < Gush::Job; end
class FetchSecondJob < Gush::Job; end
class PersistFirstJob < Gush::Job; end
class PersistSecondJob < Gush::Job; end
class NormalizeJob < Gush::Job; end
class BobJob < Gush::Job; end

GUSHFILE  = Pathname.new(__FILE__).parent.join("Gushfile.rb")

class TestWorkflow < Gush::Workflow
  def configure
    run Prepare

    run NormalizeJob

    run FetchFirstJob,   after: Prepare
    run FetchSecondJob,  after: Prepare, before: NormalizeJob

    run PersistFirstJob, after: FetchFirstJob, before: NormalizeJob

  end
end

class Redis
  def publish(*)
  end
end

REDIS_URL = "redis://localhost:6379/12"

module GushHelpers
  def redis
    @redis ||= Redis.new(url: REDIS_URL)
  end

  def jobs_with_id(jobs_array)
    jobs_array.map {|job_name| job_with_id(job_name) }
  end

  def job_with_id(job_name)
    /#{job_name}-(?<identifier>.*)/
  end
end

RSpec::Matchers.define :have_jobs do |flow, jobs|
  match do |actual|
    expected = jobs.map do |job|
      hash_including("args" => include(flow, job))
    end
    expect(Gush::Worker.jobs).to match_array(expected)
  end

  failure_message do |actual|
    "expected queue to have #{jobs}, but instead has: #{actual.jobs.map{ |j| j["args"][1]}}"
  end
end

RSpec.configure do |config|
  config.include GushHelpers

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.before(:each) do
    Gush.configure do |config|
      config.redis_url = REDIS_URL
      config.environment = 'test'
      config.gushfile = GUSHFILE
    end
  end


  config.after(:each) do
    Sidekiq::Worker.clear_all
    redis.flushdb
  end
end
