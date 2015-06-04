module Gush
  class Job
    attr_accessor :workflow_id, :incoming, :outgoing, :params,
      :finished_at, :failed_at, :started_at, :enqueued_at, :payloads
    attr_reader :name, :output_payload, :params

    def initialize(workflow, opts = {})
      @workflow = workflow
      options = opts.dup
      assign_variables(options)
    end

    def as_json
      {
        name: name,
        klass: self.class.to_s,
        incoming: incoming,
        outgoing: outgoing,
        finished_at: finished_at,
        enqueued_at: enqueued_at,
        started_at: started_at,
        failed_at: failed_at,
        params: params,
        output_payload: output_payload
      }
    end

    def to_json(options = {})
      Gush::JSON.encode(as_json)
    end

    def self.from_hash(flow, hash)
      hash[:klass].constantize.new(flow, hash)
    end

    def output(data)
      @output_payload = data
    end

    def work
    end

    def start!
      @started_at = current_timestamp
    end

    def enqueue!
      @enqueued_at = current_timestamp
      @started_at = nil
      @finished_at = nil
      @failed_at = nil
    end

    def finish!
      @finished_at = current_timestamp
    end

    def fail!
      @finished_at = @failed_at = current_timestamp
    end

    def enqueued?
      !!enqueued_at
    end

    def finished?
      !!finished_at
    end

    def failed?
      !!failed_at
    end

    def succeeded?
      finished? && !failed?
    end

    def running?
      !!started_at && !finished?
    end

    def ready_to_start?
      !running? && !enqueued? && !finished? && !failed?
    end

    def has_no_dependencies?
      incoming.empty?
    end

    private
    def current_timestamp
      Time.now.to_i
    end

    def assign_variables(opts)
      @name           = opts[:name]
      @incoming       = opts[:incoming] || []
      @outgoing       = opts[:outgoing] || []
      @failed_at      = opts[:failed_at]
      @finished_at    = opts[:finished_at]
      @started_at     = opts[:started_at]
      @enqueued_at    = opts[:enqueued_at]
      @params         = opts[:params] || {}
      @output_payload = opts[:output_payload]
    end
  end
end
