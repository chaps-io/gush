require "bundler/setup"
require "securerandom"
require "gush/version"
require "gush/concurrent_workflow"
require "gush/workflow"
require "gush/job"
require "gush/cli"
require "hiredis"
require "redis"
require "sidekiq"
require "graphviz"
require "pathname"

module Gush
  def self.root
    Pathname.new(FileUtils.pwd)
  end

  def self.tree_from_hash(hash)
    node = hash["json_class"].constantize.new(hash["name"],
      finished: hash["finished"],
      enqueued: hash["enqueued"],
      failed: hash["failed"],
      configure: false)

    if hash["children"]
      hash["children"].each do |child|
        node << tree_from_hash(child)
      end
    end
    node
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

    workflow.next_jobs.each do |job|
      job.class.perform_async(workflow.name, job.name)
      job.enqueue!
    end

    persist_workflow(workflow, options[:redis])
    workflow
  end

  def self.find_workflow(id, redis)
    json = redis.get("gush.workflows.#{id}")
    return nil if json.nil?
    Gush.tree_from_hash(JSON.parse(json))
  end

  def self.persist_workflow(workflow, redis)
    redis.set("gush.workflows.#{workflow.name}", workflow.to_json)
  end
end
