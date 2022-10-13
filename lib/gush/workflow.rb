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
      flow.persist!
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

      @dependencies = []
    end

    def find_job(name)
      if name =~ Gush::Client::UUID_REGEXP
        job = jobs.find { |node| node.id == name.to_s }
      else
        job = jobs.find { |node| node.class.to_s == name.to_s }
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
      node = klass.new(
        id: SecureRandom.uuid,
        params: opts.fetch(:params, {}),
        queue: opts[:queue]
      )

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

    def as_properties
      {
        id: id,
        arguments: arguments.present? ? Gush::JSON.encode(arguments) : [],
        klass: self.class.to_s,
        stopped: stopped,
      }
    end

    def self.from_properties(props)
      args = Gush::JSON.decode(props["arguments"]) if props["arguments"].present?

      props["klass"].constantize.new(*args).tap do |flow|
        flow.id = props["id"]
        flow.stopped = props["stopped"] == "true"
      end
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
  end
end
