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
require "redis-mutex"
require "sidekiq"
require "graphviz"
require "pathname"


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
    Redis::Mutex.with_lock("gush.mutex.start_workflow.#{id}", Gush.configuration.mutex) do
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
  end

  def self.find_workflow(id, redis)
    Redis::Mutex.with_lock("gush.mutex.find.#{id}", Gush.configuration.mutex) do
      json = redis.get("gush.workflows.#{id}")
      workflow = nil if json.nil?
      Gush.workflow_from_hash(JSON.parse(json))
    end
  end

  def self.persist_workflow(workflow, redis)
    Redis::Mutex.with_lock("gush.mutex.persist.#{workflow.name}", Gush.configuration.mutex) do
      redis.set("gush.workflows.#{workflow.name}", workflow.to_json)
    end
  end
end

Redis::Classy.db = Redis.new(url: Gush.configuration.redis_url)
