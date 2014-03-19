require 'sidekiq'
require 'yajl'

module Gush
  class Job < Tree::TreeNode
    include ::Sidekiq::Worker
    DEFAULTS = {
      finished: false,
      enqueued: false,
      failed: false
    }

    attr_accessor :finished, :enqueued, :failed, :workflow_id

    def initialize(name = SecureRandom.uuid, opts = {})
      super(name, nil)
      options = DEFAULTS.dup.merge(opts)
      @finished = options[:finished]
      @enqueued = options[:enqueued]
      @failed   = options[:failed]
    end

    def perform(workflow_id, name, *args)
      begin
        @workflow_id = workflow_id
        start = Time.now
        work(*args)
        mark_as_finished
        report(:finished, start)
        continue_workflow
      rescue Exception => e
        mark_as_failed
        report(:failed, start, e.message)
      end
    end

    def mark_as_finished
      workflow = find_workflow
      job = workflow.find_job(self.class.to_s)
      job.finish!
      Gush.persist_workflow(workflow, redis)
    end

    def mark_as_failed
      workflow = find_workflow
      job = workflow.find_job(self.class.to_s)
      job.fail!
      Gush.persist_workflow(workflow, redis)
    end

    def continue_workflow
      workflow = find_workflow
      Gush.start_workflow(@workflow_id, redis: redis)
    end

    def find_workflow
      Gush.find_workflow(@workflow_id, redis)
    end

    def as_json(options = {})
      hash = super(options)
      hash["finished"] = @finished
      hash["enqueued"] = @enqueued
      hash["failed"] = @failed
      hash.delete("content")
      hash
    end

    def work
    end

    def enqueue!
      @enqueued = true
    end

    def finish!
      @finished = true
      @enqueued = false
      @failed = false
    end

    def fail!
      @finished = true
      @failed = true
      @enqueued = false
    end

    private

    def report(status, start, error = nil)
      response = {status: status, workflow_id: workflow_id, job: self.class.to_s, duration: elapsed(start)}
      response[:error] = error if error
      redis.publish("gush.workers.status", encoder.encode(response))
    end

    def redis
      @redis ||= Redis.new
    end

    def elapsed(start)
      (Time.now - start).to_f.round(3)
    end

    def encoder
      @encoder ||= Yajl::Encoder.new
    end
  end
end
