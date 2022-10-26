module Gush
  class Job
    attr_accessor :id, :output_payload, :params, :workflow_id, :finished_at, :failed_at, :started_at, :enqueued_at, :payloads, :queue

    def initialize(id: nil, params: {}, queue: nil)
      @id = id
      @params = params
      @queue = queue
    end

    def as_properties
      {
        id: id,
        klass: self.class.to_s,
        queue: queue || '',
        finished_at: finished_at&.iso8601 || '',
        enqueued_at: enqueued_at&.iso8601 || '',
        started_at: started_at&.iso8601 || '',
        failed_at: failed_at&.iso8601 || '',
        params: params.present? ? Gush::JSON.encode(params) : '{}',
        output_payload: output_payload.present? ? Gush::JSON.encode(output_payload) : '{}'
      }
    end

    def self.from_properties(props)
      props["klass"].constantize.new.tap do |job|
        job.id = props["id"]
        job.failed_at = Time.parse(props["failed_at"]) rescue nil
        job.finished_at = Time.parse(props["finished_at"]) rescue nil
        job.started_at = Time.parse(props["started_at"]) rescue nil
        job.enqueued_at = Time.parse(props["enqueued_at"]) rescue nil
        job.params = Gush::JSON.decode(props["params"]) rescue {}
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
      # @failed_at = nil
    end

    def fail!
      @finished_at = @failed_at = current_timestamp
      # @enqueued_at = @started_at = nil
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
  end
end
