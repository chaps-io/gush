require 'gush'
require 'pry'
require 'sidekiq/testing'

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
    TestLogger.new(job.jid, job.name)
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

RSpec.configure do |config|
  config.before(:each) do
    Sidekiq::Worker.clear_all
    @redis = Redis.new(db: 12)
    @redis.keys("gush.workflows.*").each do |key|
      @redis.del(key)
    end
  end
end
