module Gush
  class Job
    attr_accessor :id, :output_payload, :params, :workflow_id, :incoming, :outgoing,
      :finished_at, :failed_at, :started_at, :enqueued_at, :payloads, :klass, :queue

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

    def as_properties
      {
        id: id,
        klass: klass,
        queue: queue.presence,
        finished_at: finished_at&.iso8601,
        enqueued_at: enqueued_at&.iso8601,
        started_at: started_at&.iso8601,
        failed_at: failed_at&.iso8601,
        params: params.present? ? Gush::JSON.encode(params) : nil,
        output_payload: output_payload.present? ? Gush::JSON.encode(output_payload) : nil
      }
    end

    def name
      @name ||= "#{klass}|#{id}"
    end

    def to_json(options = {})
      Gush::JSON.encode(as_json)
    end

    def self.from_properties(props)
      props["klass"].constantize.new.tap do |job|
        job.id = props["id"]
        job.failed_at = Time.parse(props["failed_at"]) rescue nil
        job.finished_at = Time.parse(props["finished_at"]) rescue nil
        job.started_at = Time.parse(props["started_at"]) rescue nil
        job.enqueued_at = Time.parse(props["enqueued_at"]) rescue nil
        job.params = Gush::JSON.decode(props["params"]) rescue nil
        job.output_payload = Gush::JSON.decode(props["output_payload"]) rescue nil
        job.queue = props["queue"].presence
      end
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
      Time.current
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
