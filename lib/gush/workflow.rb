require 'securerandom'

module Gush
  class Workflow
    attr_accessor :id, :jobs, :stopped, :connections, :persisted, :arguments

    def initialize(*args)
      @id = id
      @jobs = []
      @dependencies = []
      @connections = Set.new
      @persisted = false
      @stopped = false
      @arguments = args

      setup
    end

    def self.find(id)
      Gush::Client.new.find_workflow(id)
    end

    def self.create(*args)
      flow = new(*args)
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

    def configure(*args)
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

        connections.add([from.id, to.id])
      end
    end

    def find_job(name)
      if name =~ Gush::Client::UUID_REGEXP
        job = jobs.find { |node| node.id == name.to_s }
      else
        job = jobs.find { |node| node.klass.to_s == name.to_s }
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
        id: SecureRandom.uuid,
        params: opts.fetch(:params, {}),
        queue: opts[:queue]
      })

      jobs << node

      deps_after = [*opts[:after]]

      deps_after.each do |dep|
        @dependencies << {from: dep.to_s, to: node.id }
      end

      deps_before = [*opts[:before]]

      deps_before.each do |dep|
        @dependencies << {from: node.id, to: dep.to_s }
      end

      node.id
    end

    def reload
      flow = self.class.find(id)

      self.jobs = flow.jobs
      self.stopped = flow.stopped

      self
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
        total: jobs.count,
        finished: jobs.count(&:finished?),
        klass: name,
        status: status,
        stopped: stopped,
        started_at: started_at,
        finished_at: finished_at
      }
    end

    def as_properties
      {
        id: id,
        arguments: @arguments.present? ? Gush::JSON.encode(@arguments) : nil,
        klass: self.class.to_s,
        stopped: stopped,
        started_at: started_at&.iso8601,
        finished_at: finished_at&.iso8601
      }
    end

    def self.from_properties(props)
      props["klass"].constantize.new.tap do |flow|
        flow.id = props["id"]
        flow.arguments = Gush::JSON.decode(props["arguments"]) if props["arguments"].present?
        flow.stopped = props["stopped"] == "true"
      end
    end

    def to_json(options = {})
      Gush::JSON.encode(to_hash)
    end

    def self.descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    def id
      @id ||= SecureRandom.uuid
    end

    private

    def setup
      configure(*@arguments)
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
