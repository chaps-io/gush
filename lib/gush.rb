require "bundler/setup"
require "securerandom"
require "gush/version"
require "gush/configuration"
require "gush/workflow"
require "gush/metadata"
require "gush/job"
require "gush/cli"
require "hiredis"
require "redis"
require "sidekiq"
require "graphviz"
require "pathname"
require 'yajl'

module Gush
  def self.gushfile
    gushfile = Pathname.new(FileUtils.pwd).join("Gushfile.rb")
    raise Thor::Error, "Gushfile not found, please add it to your project".colorize(:red) unless gushfile.exist?
    gushfile
  end

  def self.root
    Pathname.new(__FILE__).parent.parent
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration) if block_given?
  end

  def self.workflow_from_hash(hash, nodes = nil)
    flow = hash[:klass].constantize.new(hash[:name], configure: false)

    (nodes || hash[:nodes]).each do |node|
      flow.nodes << Gush::Job.from_hash(node)
    end

    flow
  end

  def self.start_workflow(id, options = {})
    if options[:redis].nil?
      raise "Provide Redis connection object through options[:redis]"
    end

    workflow = find_workflow(id, options[:redis])

    if workflow.nil?
      puts "Workflow not found."
      return
    end

    jobs = if options[:jobs]
      options[:jobs].map { |name| workflow.find_job(name) }
    else
      workflow.next_jobs
    end

    jobs.each do |job|
      job.enqueue!
      persist_job(workflow.name, job, options[:redis])
      Sidekiq::Client.push({
        'class' => job.class,
        'queue' => Gush.configuration.namespace,
        'args'  => [workflow.name, Yajl::Encoder.new.encode(job.as_json)]
      })
    end
  end

  def self.find_workflow(id, redis)
    json = redis.get("gush.workflows.#{id}")
    if json.nil?
      workflow = nil
    else
      hash = Yajl::Parser.parse(json, symbolize_keys: true)
      keys = redis.keys("gush.jobs.#{id}.*")
      nodes = redis.mget(*keys).map { |json| Yajl::Parser.parse(json, symbolize_keys: true) }
      workflow = Gush.workflow_from_hash(hash, nodes)
    end
    workflow
  end

  def self.persist_workflow(workflow, redis)
    redis.set("gush.workflows.#{workflow.name}", workflow.to_json)

    workflow.nodes.each do |job|
      persist_job(workflow.name, job, redis)
    end
  end

  def self.persist_job(workflow_id, job, redis)
    redis.set("gush.jobs.#{workflow_id}.#{job.class.to_s}", job.to_json)
  end


  def self.configure_sidekiq
    Sidekiq.configure_server do |config|
      config.redis = ConnectionPool.new(size: Sidekiq.options[:concurrency] + 2, timeout: 1) do
        Redis.new(url: Gush.configuration.redis_url)
      end
    end
  end
end


Gush.configure_sidekiq
