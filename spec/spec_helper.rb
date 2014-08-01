require 'gush'
require 'pry'
require 'sidekiq/testing'
require 'bbq/spawn'

Sidekiq::Logging.logger = nil

class Prepare < Gush::Job;  end
class FetchFirstJob < Gush::Job; end
class FetchSecondJob < Gush::Job; end
class PersistFirstJob < Gush::Job; end
class PersistSecondJob < Gush::Job; end
class NormalizeJob < Gush::Job; end

TestLogger = Struct.new(:jid, :name)

class TestLoggerBuilder < Gush::LoggerBuilder
  def build
    TestLogger.new(jid, job.name)
  end
end

class TestWorkflow < Gush::Workflow
  def configure
    logger_builder TestLoggerBuilder

    run Prepare

    run NormalizeJob

    run FetchFirstJob,   after: Prepare
    run PersistFirstJob, after: FetchFirstJob, before: NormalizeJob

    run FetchSecondJob,  after: Prepare, before: NormalizeJob
  end
end

module GushHelpers
  REDIS_URL = "redis://localhost:33333/"

  def redis
    @redis ||= Redis.new(url: REDIS_URL)
  end

  def client
    @client ||= Gush::Client.new(Gush::Configuration.new(redis_url: REDIS_URL))
  end
end

RSpec.configure do |config|
  config.include GushHelpers

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  orchestrator = Bbq::Spawn::Orchestrator.new

  config.before(:suite) do
    config_path = Pathname.pwd + "spec/redis.conf"
    executor = Bbq::Spawn::Executor.new("redis-server", config_path.to_path)
    orchestrator.coordinate(executor, host: 'localhost', port: 33333)
    orchestrator.start
  end

  config.after(:suite) do
    orchestrator.stop
  end

  config.after(:each) do
    Sidekiq::Worker.clear_all
    redis.flushdb
  end
end
