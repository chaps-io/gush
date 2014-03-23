require "bundler/setup"
require "securerandom"
require "gush/version"
require "gush/configuration"
require "gush/workflow"
require "gush/metadata"
require "gush/job"
require "gush/node"
require "gush/edge"
require "gush/cli"
require "hiredis"
require "redis"
require "sidekiq"
require "graphviz"
require "pathname"

module Gush
  def self.root
    Pathname.new(__FILE__).parent.parent
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration) if block_given?
  end

  def self.workflow_from_hash(hash)
    flow = hash["klass"].constantize.new(hash["name"], configure: false)

    hash["nodes"].each do |node|
      flow.nodes << Gush::Job.from_hash(node)
    end

    hash["edges"].each do |edge|
      from = flow.find_job(edge["from"])
      to = flow.find_job(edge["to"])

      from.connect_to(to)
      to.connect_from(from)
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

    if options[:jobs]
      jobs = options[:jobs].map { |name| workflow.find_job(name) }
    else
      jobs = workflow.next_jobs
    end

    jobs.each do |job|
      job.class.perform_async(workflow.name, job.name)
      job.enqueue!
    end

    persist_workflow(workflow, options[:redis])
    jobs
  end

  def self.find_workflow(id, redis)
    json = redis.get("gush.workflows.#{id}")
    return nil if json.nil?
    Gush.workflow_from_hash(JSON.parse(json))
  end

  def self.persist_workflow(workflow, redis)
    redis.set("gush.workflows.#{workflow.name}", workflow.to_json)
  end
end
