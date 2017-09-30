require 'active_job'

module Gush
  class Worker < ::ActiveJob::Base
    def perform(workflow_id, job_id)
      setup_job(workflow_id, job_id)

      job.payloads = incoming_payloads

      start = Time.now
      report(:started, start)

      failed = false
      error = nil

      mark_as_started
      begin
        job.perform
      rescue StandardError => error
        mark_as_failed
        report(:failed, start, error.message)
        raise error
      else
        mark_as_finished
        report(:finished, start)

        enqueue_outgoing_jobs
      end
    end

    private

    attr_reader :client, :workflow, :job

    def client
      @client ||= Gush::Client.new(Gush.configuration)
    end

    def setup_job(workflow_id, job_id)
      @workflow ||= client.find_workflow(workflow_id)
      @job ||= workflow.find_job(job_id)
    end

    def incoming_payloads
      job.incoming.map do |job_name|
        job = client.find_job(workflow.id, job_name)
        {
          id: job.name,
          class: job.klass.to_s,
          output: job.output_payload
        }
      end
    end

    def mark_as_finished
      job.finish!
      client.persist_job(workflow.id, job)
    end

    def mark_as_failed
      job.fail!
      client.persist_job(workflow.id, job)
    end

    def mark_as_started
      job.start!
      client.persist_job(workflow.id, job)
    end

    def report_workflow_status
      client.workflow_report({
        workflow_id:  workflow.id,
        status:       workflow.status,
        started_at:   workflow.started_at,
        finished_at:  workflow.finished_at
      })
    end

    def report(status, start, error = nil)
      message = {
        status: status,
        workflow_id: workflow.id,
        job: job.name,
        duration: elapsed(start)
      }
      message[:error] = error if error
      client.worker_report(message)
    end

    def elapsed(start)
      (Time.now - start).to_f.round(3)
    end

    def enqueue_outgoing_jobs
      job.outgoing.each do |job_name|
        out = client.find_job(workflow.id, job_name)
        if out.ready_to_start?
          client.enqueue_job(workflow.id, out)
        end
      end
    end
  end
end
