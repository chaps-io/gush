require 'active_job'
require 'redis-mutex'
require 'lazy_object'

module Gush
  class Worker < ::ActiveJob::Base
    def perform(workflow_id, job_name)
      setup_job(workflow_id, job_name)

      job.payloads = LazyObject.new { incoming_payloads }

      error = nil

      mark_as_started
      begin
        job.perform
      rescue StandardError => error
        mark_as_failed
        raise error
      else
        mark_as_finished
        enqueue_outgoing_jobs
      end
    end

    private

    attr_reader :client, :workflow_id, :job

    def client
      @client ||= Gush::Client.new(Gush.configuration)
    end

    def setup_job(workflow_id, job_name)
      @workflow_id = workflow_id
      @job ||= client.find_job(workflow_id, job_name)
    end

    def incoming_payloads
      job.incoming.map do |job_name|
        job = client.find_job(workflow_id, job_name)
        {
          id: job.name,
          class: job.klass.to_s,
          output: job.output_payload
        }
      end
    end

    def mark_as_finished
      job.finish!
      update_job
    end

    def mark_as_failed
      job.fail!
      update_job
    end

    def mark_as_started
      job.start!
      update_job
    end

    def update_job
      client.persist_job(workflow_id, job)
    end

    def enqueue_outgoing_jobs
      queue_names = client.find_job_attributes(workflow_id, job.outgoing, ["queue"])
      job.outgoing.zip(queue_names).each do |job_name, (queue)|
        RedisMutex.with_lock("gush_enqueue_outgoing_jobs_#{workflow_id}-#{job_name}", sleep: 0.3, block: 2) do
          if client.job_has_dependencies_satisfied?(workflow_id, job_name)
            client.enqueue_job_by_name_and_queue(workflow_id, job_name, queue)
          end
        end
      end
    end
  end
end
