require "bundler/setup"

require "graphviz"
require "hiredis"
require "pathname"
require "redis"
require "securerandom"
require "sidekiq"

require "gush/cli"
require "gush/graph"
require "gush/client"
require "gush/configuration"
require "gush/errors"
require "gush/job"
require "gush/logger_builder"
require "gush/metadata"
require "gush/null_logger"
require "gush/version"
require "gush/worker"
require "gush/workflow"

module Gush
  def self.gushfile
    configuration.gushfile
  end

  def self.root
    Pathname.new(__FILE__).parent.parent
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration
    reconfigure_sidekiq_server
  end

  def self.reconfigure_sidekiq_server
    Sidekiq.configure_server do |config|
      config.redis = { url: configuration.redis_url, queue: configuration.namespace}
    end
  end
end

Gush.reconfigure_sidekiq_server
