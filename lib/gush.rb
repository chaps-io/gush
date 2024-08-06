require "bundler/setup"

require "graphviz"
require "hiredis"
require "pathname"
require "redis"
require "securerandom"
require "multi_json"

require "gush/json"
require "gush/cli"
require "gush/cli/overview"
require "gush/graph"
require "gush/client"
require "gush/configuration"
require "gush/errors"
require "gush/job"
require "gush/migration"
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
  end
end
