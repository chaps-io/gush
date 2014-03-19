require 'tree'
require 'securerandom'
require 'gush/concurrent_workflow'
require 'gush/printable'
require 'gush/metadata'

module Gush
  class Workflow < Tree::TreeNode
    include Gush::Printable
    include Gush::Metadata

    attr_accessor :last_node

    def initialize(name, options = {})
      super(name, nil)
      configure unless options[:configure] == false
    end

    def start
    end

    def configure
    end

    def find_job(name)
      breadth_each.find { |node| node.name == name || node.class.to_s == name }
    end

    def next_jobs
      return [] if failed?

      by_level = jobs
        .group_by(&:node_depth)

      by_level.each do |level, jobs|
        break if jobs.any?(&:running?)
        filtered_jobs = jobs.reject(&:finished?)
        return filtered_jobs if filtered_jobs.any?
      end
      []
    end

    def jobs
      breadth_each.select { |n| n.class <= Gush::Job }
    end

    def finished?
      jobs.all?(&:finished)
    end

    def running?
      jobs.any?(&:enqueued)
    end

    def failed?
      jobs.any?(&:failed)
    end

    def run(klass, attach_concurrently = false)
      node = klass.new(klass.to_s)
      if attach_concurrently
        self << node
      else
        deepest_node << node
      end
    end

    def concurrently(custom_name = nil, &block)
      name = (custom_name || "concurrent-#{SecureRandom.uuid}").to_s
      flow = Gush::ConcurrentWorkflow.new(name)
      flow.eval_in_context(block)

      deepest_node << flow
    end

    def synchronously(custom_name = nil, attach_concurrently = false, &block)
      name = (custom_name || "sync-#{SecureRandom.uuid}").to_s
      flow = Gush::Workflow.new(name)
      flow.eval_in_context(block)

      if attach_concurrently
        self << flow
      else
        deepest_node << flow
      end
    end

    def as_json(options = {})
      hash = super(options)
      hash.delete("content")
      hash
    end

    def eval_in_context(block)
      instance_eval(&block)
    end

    def deepest_node
      each_leaf.sort_by{|n| -n.node_depth }.first
    end
  end
end
