require 'securerandom'

module Gush
  class Workflow
    attr_accessor :id, :jobs, :dependencies, :stopped, :persisted, :arguments, :kwargs, :globals

    def initialize(*args, globals: nil, internal_state: {}, **kwargs)
      @arguments = args
      @kwargs = kwargs
      @globals = globals || {}

      @id = internal_state[:id] || id
      @jobs = internal_state[:jobs] || []
      @dependencies = internal_state[:dependencies] || []
      @persisted = internal_state[:persisted] || false
      @stopped = internal_state[:stopped] || false

      setup unless internal_state[:skip_setup]
    end

    def self.find(id)
      Gush::Client.new.find_workflow(id)
    end

    def self.create(*args, **kwargs)
      flow = new(*args, **kwargs)
      flow.save
      flow
    end

    def continue
      client = Gush::Client.new
      failed_jobs = jobs.select(&:failed?)

      failed_jobs.each do |job|
        client.enqueue_job(id, job)
      end
    end

    def save
      persist!
    end

    def configure(*args, **kwargs)
    end

    def mark_as_stopped
      @stopped = true
    end

    def start!
      client.start_workflow(self)
    end

    def persist!
      client.persist_workflow(self)
    end

    def expire! (ttl=nil)
      client.expire_workflow(self, ttl)
    end

    def mark_as_persisted
      @persisted = true
    end

    def mark_as_started
      @stopped = false
    end

    def resolve_dependencies
      @dependencies.each do |dependency|
        from = find_job(dependency[:from])
        to   = find_job(dependency[:to])

        to.incoming << dependency[:from]
        from.outgoing << dependency[:to]
      end
    end

    def find_job(name)
      match_data = /(?<klass>\w*[^-])-(?<identifier>.*)/.match(name.to_s)

      if match_data.nil?
        job = jobs.find { |node| node.klass.to_s == name.to_s }
      else
        job = jobs.find { |node| node.name.to_s == name.to_s }
      end

      job
    end

    def finished?
      jobs.all?(&:finished?)
    end

    def started?
      !!started_at
    end

    def running?
      started? && !finished?
    end

    def failed?
      jobs.any?(&:failed?)
    end

    def stopped?
      stopped
    end

    def run(klass, opts = {})
      node = klass.new({
        workflow_id: id,
        id: client.next_free_job_id(id, klass.to_s),
        params: (@globals || {}).merge(opts.fetch(:params, {})),
        queue: opts[:queue],
        wait: opts[:wait]
      })

      jobs << node

      deps_after = [*opts[:after]]

      deps_after.each do |dep|
        @dependencies << {from: dep.to_s, to: node.name.to_s }
      end

      deps_before = [*opts[:before]]

      deps_before.each do |dep|
        @dependencies << {from: node.name.to_s, to: dep.to_s }
      end

      node.name
    end

    def reload
      flow = self.class.find(id)

      self.jobs = flow.jobs
      self.stopped = flow.stopped

      self
    end

    def initial_jobs
      jobs.select(&:has_no_dependencies?)
    end

    def status
      case
        when failed?
          :failed
        when running?
          :running
        when finished?
          :finished
        when stopped?
          :stopped
        else
          :running
      end
    end

    def started_at
      first_job ? first_job.started_at : nil
    end

    def finished_at
      last_job ? last_job.finished_at : nil
    end

    def to_hash
      name = self.class.to_s
      {
        name: name,
        id: id,
        arguments: @arguments,
        kwargs: @kwargs,
        globals: @globals,
        dependencies: @dependencies,
        total: jobs.count,
        finished: jobs.count(&:finished?),
        klass: name,
        status: status,
        stopped: stopped,
        started_at: started_at,
        finished_at: finished_at
      }
    end

    def to_json(options = {})
      Gush::JSON.encode(to_hash)
    end

    def self.descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    def id
      @id ||= client.next_free_workflow_id
    end

    private

    def setup
      configure(*@arguments, **@kwargs)
      resolve_dependencies
    end

    def client
      @client ||= Client.new
    end

    def first_job
      jobs.min_by{ |n| n.started_at || Time.now.to_i }
    end

    def last_job
      jobs.max_by{ |n| n.finished_at || 0 } if finished?
    end
  end
end
