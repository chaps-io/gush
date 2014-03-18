require 'bundler/setup'
require 'securerandom'
require "gush/version"
require "gush/concurrent_workflow"
require "gush/workflow"
require "gush/job"

require 'hiredis'
require 'redis'
require 'sidekiq'
require 'graphviz'
require 'pathname'

module Gush
  def self.root
    Pathname.new(FileUtils.pwd)
  end

  def self.tree_from_hash(hash)
    node = hash["json_class"].constantize.new(hash["name"], hash["finished"], hash["enqueued"], hash["failed"], false)

    if hash["children"]
      hash["children"].each do |child|
        node << tree_from_hash(child)
      end
    end

    node
  end

  def self.start_workflow(id, redis)
    hash = JSON.parse(redis.get("gush.workflows.#{id}"))
    workflow = Gush.tree_from_hash(hash)

    workflow.next_jobs.each do |job|
      job.class.perform_async(workflow.name, job.name)
      job.enqueue!
    end

    redis.set("gush.workflows.#{id}", workflow.to_json)
  end
end
