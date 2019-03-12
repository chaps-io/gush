module Gush
  class Job
    attr_accessor :workflow_id, :incoming, :outgoing, :params,
      :finished_at, :failed_at, :started_at, :enqueued_at, :payloads, :klass, :queue
    attr_reader :id, :klass, :output_payload, :params

    def initialize(opts = {})
      options = opts.dup
      assign_variables(options)
    end

    def as_json
      {
        id: id,
        klass: klass.to_s,
        queue: queue,
        incoming: incoming,
        outgoing: outgoing,
        finished_at: finished_at,
        enqueued_at: enqueued_at,
        started_at: started_at,
        failed_at: failed_at,
        params: params,
        workflow_id: workflow_id,
        output_payload: output_payload
      }
    end

    def name
      @name ||= "#{klass}|#{id}"
    end

    def to_json(options = {})
      Gush::JSON.encode(as_json)
    end

    def self.from_hash(hash)
      hash[:klass].constantize.new(hash)
    end

    def output(data)
      @output_payload = data
    end

    def perform
    end

    def start!
      @started_at = current_timestamp
      @failed_at = nil
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
      !enqueued_at.nil?
    end

    def finished?
      !finished_at.nil?
    end

    def failed?
      !failed_at.nil?
    end

    def succeeded?
      finished? && !failed?
    end

    def started?
      !started_at.nil?
    end

    def running?
      started? && !finished?
    end

    def ready_to_start?
      !running? && !enqueued? && !finished? && !failed? && parents_succeeded?
    end

    def parents_succeeded?
      !incoming.any? do |name|
        !client.find_job(workflow_id, name).succeeded?
      end
    end

    def has_no_dependencies?
      incoming.empty?
    end

    private

    def client
      @client ||= Client.new
    end

    def current_timestamp
      Time.now.to_i
    end

    def assign_variables(opts)
      @id             = opts[:id]
      @incoming       = opts[:incoming] || []
      @outgoing       = opts[:outgoing] || []
      @failed_at      = opts[:failed_at]
      @finished_at    = opts[:finished_at]
      @started_at     = opts[:started_at]
      @enqueued_at    = opts[:enqueued_at]
      @params         = opts[:params] || {}
      @klass          = opts[:klass] || self.class
      @output_payload = opts[:output_payload]
      @workflow_id    = opts[:workflow_id]
      @queue          = opts[:queue]
    end
  end
end
