require 'active_job'
require 'redis-mutex'

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
        catch(:skipped_job) do
          job.perform
        end
      rescue StandardError => error
        mark_as_failed
        raise error
      else
        mark_as_finished
        enqueue_outgoing_jobs
      end
    end

    private

    attr_reader :workflow_id, :job

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

    def enqueue_outgoing_jobs
      job.outgoing.each do |job_name|
        RedisMutex.with_lock(
          "gush_enqueue_outgoing_jobs_#{workflow_id}-#{job_name}",
          sleep: configuration.polling_interval,
          block: configuration.locking_duration
        ) do
          out = client.find_job(workflow_id, job_name)

          if out.ready_to_start?
            client.enqueue_job(workflow_id, out)
          end
        end
      end
    rescue RedisMutex::LockError
      Worker.set(wait: 2.seconds).perform_later(workflow_id, job.name)
    end
  end
end
