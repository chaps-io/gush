require "bundler/setup"
require "securerandom"
require "gush/version"
require "gush/configuration"
require "gush/workflow"
require "gush/metadata"
require "gush/job"
require "gush/cli"
require "gush/logger_builder"
require "gush/null_logger"
require "gush/errors"
require "hiredis"
require "redis"
require "sidekiq"
require "graphviz"
require "pathname"
require 'yajl'

module Gush
  def self.gushfile
    path = Pathname.pwd.join("Gushfile.rb")
    raise Thor::Error, "Gushfile.rb not found, please add it to your project".colorize(:red) unless path.exist?
    path
  end

  def self.root
    Pathname.new(__FILE__).parent.parent
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure(&block)
    yield(configuration) if block_given?
  end

  def self.workflow_from_hash(hash, nodes = nil)
    flow = hash[:klass].constantize.new(hash[:id], configure: false)
    flow.logger_builder(hash[:logger_builder].constantize)
    flow.stopped = hash[:stopped]

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
    workflow.start!
    Gush.persist_workflow(workflow, options[:redis])

    jobs = if options[:jobs]
      options[:jobs].map { |name| workflow.find_job(name) }
    else
      workflow.next_jobs
    end

    jobs.each do |job|
      job.enqueue!
      persist_job(workflow.id, job, options[:redis])
      Sidekiq::Client.push({
        'class' => job.class,
        'queue' => Gush.configuration.namespace,
        'args'  => [workflow.id, Yajl::Encoder.new.encode(job.as_json)]
      })
    end
  rescue WorkflowNotFoundError
    puts "Workflow not found."
  end

  def self.stop_workflow(id, options = {})
    if options[:redis].nil?
      raise "Provide Redis connection object through options[:redis]"
    end

    workflow = find_workflow(id, options[:redis])
    workflow.stop!
    Gush.persist_workflow(workflow, options[:redis])
  rescue WorkflowNotFoundError
    puts "Workflow not found."
  end

  def self.find_workflow(id, redis)
    data = redis.get("gush.workflows.#{id}")
    unless data.nil?
      hash = Yajl::Parser.parse(data, symbolize_keys: true)
      keys = redis.keys("gush.jobs.#{id}.*")
      nodes = redis.mget(*keys).map { |json| Yajl::Parser.parse(json, symbolize_keys: true) }
      Gush.workflow_from_hash(hash, nodes)
    else
      raise WorkflowNotFoundError.new("Workflow with given id doesn't exist")
    end
  end

  def self.create_workflow(name, redis)
    id = SecureRandom.uuid.split("-").first
    workflow = name.constantize.new(id)
    Gush.persist_workflow(workflow, redis)
    workflow
  end

  def self.all_workflows(redis)
    redis.keys("gush.workflows.*").map do |key|
      id = key.sub("gush.workflows.", "")
      Gush.find_workflow(id, redis)
    end
  end

  def self.persist_workflow(workflow, redis)
    redis.set("gush.workflows.#{workflow.id}", workflow.to_json)

    workflow.nodes.each do |job|
      persist_job(workflow.id, job, redis)
    end
  end

  def self.destroy_workflow(workflow, redis)
    redis.del("gush.workflows.#{workflow.id}")
    workflow.nodes.each do |job|
      redis.del("gush.jobs.#{workflow.id}.#{job.class.to_s}")
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
