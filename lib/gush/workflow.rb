require 'securerandom'

module Gush
  class Workflow
    attr_accessor :id, :jobs, :stopped

    def initialize(should_run_configure = true)
      @id = id
      @jobs = []
      @dependencies = []
      @stopped = false

      if should_run_configure
        configure
        create_dependencies
      end
    end

    def self.create(*args)
      flow = new(*args)
      flow.save
      flow
    end

    def save
      @id = client.next_free_id
      client.persist_workflow(self)
    end

    def configure
    end

    def stop!
      @stopped = true
    end

    def start!
      @stopped = false
    end

    def create_dependencies
      @dependencies.each do |dependency|
        from = find_job(dependency[:from])
        to   = find_job(dependency[:to])

        to.incoming << dependency[:from]
        from.outgoing << dependency[:to]
      end
    end

    def find_job(name)
      @jobs.find { |node| node.name == name.to_s || node.class.to_s == name.to_s }
    end

    def finished?
      jobs.all?(&:finished)
    end

    def running?
      !stopped? && jobs.any? {|j| j.enqueued? || j.running? }
    end

    def failed?
      jobs.any?(&:failed)
    end

    def stopped?
      stopped
    end

    def run(klass, deps = {})
      node = klass.new(self, name: klass.to_s)
      @jobs << node

      deps_after = [*deps[:after]]
      deps_after.each do |dep|
        @dependencies << {from: dep.to_s, to: klass.to_s }
      end

      deps_before = [*deps[:before]]
      deps_before.each do |dep|
        @dependencies << {from: klass.to_s, to: dep.to_s }
      end
    end

    def status
      case
        when failed?
          "Failed"
        when running?
          "Running"
        when finished?
          "Finished"
        when stopped?
          "Stopped"
        else
          "Pending"
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
        id: @id,
        total: @jobs.count,
        finished: @jobs.count(&:finished?),
        klass: name,
        jobs: @jobs.map(&:as_json),
        status: status,
        stopped: stopped,
        started_at: started_at,
        finished_at: finished_at
      }
    end

    def to_json(options = {})
      JSON.dump(to_hash)
    end

    def next_jobs
      jobs.select(&:can_be_started?)
    end

    def self.descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    private

    def client
      @client ||= Client.new
    end

    def first_job
      jobs.min_by{ |n| n.started_at || Time.now.to_i }
    end

    def last_job
      jobs.max_by{ |n| n.finished_at || 0 } if jobs.all?(&:finished?)
    end
  end
end
