require 'sidekiq'
require 'yajl'
require 'gush/metadata'

module Gush
  class Job
    include ::Sidekiq::Worker
    include Gush::Metadata

    sidekiq_options retry: false

    DEFAULTS = {
      finished: false,
      enqueued: false,
      failed: false
    }

    attr_accessor :finished, :enqueued, :failed, :workflow_id, :incoming, :outgoing

    def initialize(name = nil, opts = {})
      options = DEFAULTS.dup.merge(opts)
      @name = name
      @finished = options[:finished]
      @enqueued = options[:enqueued]
      @failed   = options[:failed]
      @incoming = options[:incoming] || []
      @outgoing = options[:outgoing] || []
    end

    def perform(workflow_id, name, *args)
      begin
        @workflow_id = workflow_id
        start = Time.now
        work(*args)
        mark_as_finished
        #report(:finished, start)
        continue_workflow
      rescue Exception => e
        mark_as_failed
        #report(:failed, start, e.message)
      end
    end

    def mark_as_finished
      Redis::Mutex.with_lock("gush.mutex.mark_as_finished.#{@workflow_id}", Gush.configuration.mutex) do
        self.finish!
        Gush.persist_job(@workflow_id, self, redis)
      end
    end

    def mark_as_failed
      Redis::Mutex.with_lock("gush.mutex.mark_as_failed.#{@workflow_id}", Gush.configuration.mutex) do
        self.fail!
        Gush.persist_job(@workflow_id, self, redis)
      end
    end

    def continue_workflow
      Redis::Mutex.with_lock("gush.mutex.continue_workflow.#{@workflow_id}", Gush.configuration.mutex) do
        workflow = find_workflow
        Gush.start_workflow(@workflow_id, redis: redis)
      end
    end

    def find_workflow
      Redis::Mutex.with_lock("gush.mutex.find_workflow.#{@workflow_id}", Gush.configuration.mutex) do
        Gush.find_workflow(@workflow_id, redis)
      end
    end

    def as_json
      hash = {
        name: name,
        klass: self.class.to_s,
        finished: @finished,
        enqueued: @enqueued,
        failed: @failed,
        incoming: incoming,
        outgoing: outgoing
      }
      hash
    end

    def to_json
      as_json.to_json
    end

    def self.from_hash(hash)
      job = hash["klass"].constantize.new(hash["name"],
        finished: hash["finished"],
        enqueued: hash["enqueued"],
        failed: hash["failed"],
        incoming: hash["incoming"],
        outgoing: hash["outgoing"]
      )
    end

    def work
    end

    def enqueue!
      @enqueued = true
      @failed   = false
    end

    def finish!
      @finished = true
      @enqueued = false
      @failed   = false
    end

    def fail!
      @finished = true
      @failed   = true
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

    def can_be_started?(flow)
      !running? &&
        !finished? &&
          !failed? &&
            dependencies_satisfied?(flow)
    end

    def dependencies(flow)
      (incoming.map {|name| flow.find_job(name) } + incoming.flat_map{ |name| flow.find_job(name).dependencies(flow) }).uniq
    end

    private

    def dependencies_satisfied?(flow)
      dependencies(flow).all? { |dep| !dep.running? && dep.finished? && !dep.failed? }
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
