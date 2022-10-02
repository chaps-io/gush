require 'active_job'
require 'redlock'

module Gush
  class Worker < ::ActiveJob::Base
    def perform(workflow_id, job_id)
      setup_job(workflow_id, job_id)

      if job.succeeded?
        # Try to enqueue outgoing jobs again because the last job has redis mutex lock error
        enqueue_outgoing_jobs
        return
      end

      job.payloads = incoming_payloads

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

    attr_reader :client, :workflow_id, :job, :configuration

    def client
      @client ||= Gush::Client.new(Gush.configuration)
    end

    def configuration
      @configuration ||= client.configuration
    end

    def setup_job(workflow_id, job_id)
      @workflow_id = workflow_id
      @job ||= client.find_job(workflow_id, job_id)
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
      client.persist_job(workflow_id, job)
    end

    def mark_as_failed
      job.fail!
      client.persist_job(workflow_id, job)
    end

    def mark_as_started
      job.start!
      client.persist_job(workflow_id, job)
    end

    def elapsed(start)
      (Time.now - start).to_f.round(3)
    end

     # Expose locking mechanism in gush client as public API
    def enqueue_outgoing_jobs
      client.redis.with do |conn|
        redlock = Redlock::Client.new([conn], retry_delay: configuration.polling_interval)
        job.outgoing.each do |job_name|
          redlock.lock!("gush_job_lock_#{workflow_id}-#{job_name}", configuration.locking_duration) do
            out = client.find_job(workflow_id, job_name)

            if out.ready_to_start?
              client.enqueue_job(workflow_id, out)
            end
          end
        end
      end
    rescue Redlock::LockError
      Worker.set(wait: 2.seconds).perform_later(workflow_id, job.name)
    end
  end
end
