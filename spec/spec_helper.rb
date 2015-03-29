require 'gush'
require 'pry'
require 'sidekiq/testing'
require "fakeredis"

Sidekiq::Logging.logger = nil

class Prepare < Gush::Job;  end
class FetchFirstJob < Gush::Job; end
class FetchSecondJob < Gush::Job; end
class PersistFirstJob < Gush::Job; end
class PersistSecondJob < Gush::Job; end
class NormalizeJob < Gush::Job; end

GUSHFILE  = Pathname.new(__FILE__).parent.join("Gushfile.rb")

class TestWorkflow < Gush::Workflow
  def configure
    run Prepare

    run NormalizeJob

    run FetchFirstJob,   after: Prepare
    run PersistFirstJob, after: FetchFirstJob, before: NormalizeJob

    run FetchSecondJob,  after: Prepare, before: NormalizeJob
  end
end

class Redis
  def publish(*)
  end
end

module GushHelpers
  REDIS_URL = "redis://localhost:33333/"

  def redis
    @redis ||= Redis.new(url: REDIS_URL)
  end

  def client
    @client ||= Gush::Client.new(Gush::Configuration.new(gushfile: GUSHFILE, redis_url: REDIS_URL))
  end
end

RSpec.configure do |config|
  config.include GushHelpers

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.after(:each) do
    Sidekiq::Worker.clear_all
    redis.flushdb
  end
end
