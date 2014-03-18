require 'tree'
require 'securerandom'
require 'gush/concurrent_workflow'
module Gush
  class Workflow < Tree::TreeNode

    attr_accessor :last_node

    def initialize(name, finished = false, enqueued = false, failed = false, run_configure = true)
      super(name, nil)
      configure if run_configure
    end

    def self.metadata(params = {})
      @metadata = (@metadata || {}).merge(params)
    end

    def name
      metadata[:name] || @name
    end

    def start
    end

    def configure
    end

    def find_job(name)
      self.breadth_each do |node|
        return node if node.name == name
      end
      nil
    end

    def next_jobs
      jobs = []
      self.breadth_each do |node|
        next if node.class <= Gush::Workflow
        break if ([node] + node.siblings).any? { |n| n.enqueued || n.failed }
        if !node.finished && !node.enqueued && (jobs.empty? || node.level <= jobs.last.level)
          jobs << node
        end
      end
      jobs
    end

    def jobs
      breadth_each.select { |n| n.class <= Gush::Job }
    end

    def finished?
      jobs
        .all? { |n| n.finished }
    end

    def running?
      jobs
        .any? { |n| n.enqueued }
    end

    def run(klass, attach_to_self = false)
      node = klass.new(klass.to_s)
      if attach_to_self || @last_node.nil?
        self << node
      else
        @last_node << node
      end
      if klass <= Gush::Workflow
        @last_node = node.children.first
      elsif klass <= Gush::Job
        @last_node = node
      end
    end

    def concurrently(custom_name = nil, &block)
      name = (custom_name || "concurrent-#{SecureRandom.uuid[0..6]}").to_s
      flow = Gush::ConcurrentWorkflow.new(name)
      flow.eval_in_context(block)

      if @last_node.nil?
        self << flow
      else
        @last_node << flow
      end
      @last_node = flow.children.first
    end

    def as_json(options = {})
      hash = super(options)
      hash.delete("content")
      hash
    end

    def eval_in_context(block)
      instance_eval(&block)
    end

    private
    def metadata
      self.class.metadata
    end
  end
end
