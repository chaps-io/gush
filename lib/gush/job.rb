require 'sidekiq'
require 'yajl'
require 'gush/metadata'
require 'gush/node'

module Gush
  class Job < Node
    include ::Sidekiq::Worker
    include Gush::Metadata

    sidekiq_options retry: false

    DEFAULTS = {
      finished: false,
      enqueued: false,
      failed: false
    }

    attr_accessor :finished, :enqueued, :failed, :workflow_id

    def initialize(name = nil, opts = {})
      super(name)
      options = DEFAULTS.dup.merge(opts)
      @name = name
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
      job = workflow.find_job(@name)
      job.finish!
      Gush.persist_workflow(workflow, redis)
    end

    def mark_as_failed
      workflow = find_workflow
      job = workflow.find_job(@name)
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

    def as_json
      hash = {
        name: name,
        klass: self.class.to_s,
        finished: @finished,
        enqueued: @enqueued,
        failed: @failed
      }
      hash
    end

    def self.from_hash(hash)
      job = hash["klass"].constantize.new(hash["name"], finished: hash["finished"],
        enqueued: hash["enqueued"], failed: hash["failed"])
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

    def finished?
      !!finished
    end

    def failed?
      !!failed
    end

    def running?
      !!enqueued
    end

    def can_be_started?
      !running? &&
        !finished? &&
          !failed? &&
            dependencies_satisfied?
    end

    private

    def dependencies_satisfied?
      dependencies.all? { |dep| !dep.running? && dep.finished? && !dep.failed? }
    end

    def report(status, start, error = nil)
      response = {status: status, workflow_id: workflow_id, job: @name, duration: elapsed(start)}
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
