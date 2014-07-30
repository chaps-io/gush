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
    configure_sidekiq
    @redis = build_redis
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

  def self.start_workflow(id, jobs = [])
    workflow = find_workflow(id)
    workflow.start!
    persist_workflow(workflow)

    jobs = workflow.next_jobs if jobs.empty?

    jobs.each do |job|
      job.enqueue!
      persist_job(workflow.id, job)
      enqueue_job(workflow.id, job)
    end
  end

  def self.stop_workflow(id)
    workflow = find_workflow(id)
    workflow.stop!
    persist_workflow(workflow)
  end

  def self.find_workflow(id)
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

  def self.create_workflow(name)
    id = SecureRandom.uuid.split("-").first
    workflow = name.constantize.new(id)
    persist_workflow(workflow)
    workflow
  end

  def self.all_workflows
    redis.keys("gush.workflows.*").map do |key|
      id = key.sub("gush.workflows.", "")
      find_workflow(id)
    end
  end

  def self.persist_workflow(workflow)
    redis.set("gush.workflows.#{workflow.id}", workflow.to_json)
    workflow.nodes.each {|job| persist_job(workflow.id, job) }
  end

  def self.destroy_workflow(workflow)
    redis.del("gush.workflows.#{workflow.id}")
    workflow.nodes.each {|job| destroy_job(workflow.id, job) }
  end

  def self.persist_job(workflow_id, job)
    redis.set("gush.jobs.#{workflow_id}.#{job.class.to_s}", job.to_json)
  end

  def self.enqueue_job(workflow_id, job)
    Sidekiq::Client.push({
      'class' => job.class,
      'queue' => Gush.configuration.namespace,
      'args'  => [workflow_id, Yajl::Encoder.new.encode(job.as_json)]
    })
  end

  def self.destroy_job(workflow_id, job)
    redis.del("gush.jobs.#{workflow_id}.#{job.class.to_s}")
  end

  def self.redis
    @redis ||= build_redis
  end

  def self.build_redis
    Redis.new(url: Gush.configuration.redis_url)
  end

  def self.configure_sidekiq
    Sidekiq.configure_server do |config|
      config.redis = ConnectionPool.new(size: Sidekiq.options[:concurrency] + 2, timeout: 1) do
        build_redis
      end
    end
  end
end

Gush.configure_sidekiq
