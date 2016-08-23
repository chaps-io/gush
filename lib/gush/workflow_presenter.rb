require 'sidekiq/web_helpers'

module Gush
  class WorkflowPresenter
    include Sidekiq::WebHelpers

    attr_reader :workflow

    def initialize(workflow)
      @workflow = workflow
    end

    def id
      workflow.id
    end

    def name
      workflow.class.to_s
    end

    def jobs
      total_jobs_count
    end

    def failed_jobs
      failed_jobs_count
    end

    def succeeded_jobs
      succeeded_jobs_count
    end

    def enqueued_jobs
      enqueued_jobs_count
    end

    def running_jobs
      running_jobs_count
    end

    def remaining_jobs
      remaining_jobs_count
    end

    def started_at
      started_at
    end

    def status
      if workflow.failed?
        failed_status
      elsif workflow.running?
        running_status
      elsif workflow.finished?
        "done".green
      elsif workflow.stopped?
        "stopped".red
      else
        "ready to start".blue
      end
    end

    def started_at
      relative_time(Time.at(workflow.started_at))
    end

    # Builds the array used to display the workflows web page
    #
    # @return [Array<Gush::CLI::Overview>]
    def self.build_collection
      # TODO: Should "gush." be dynamic based on namespace?
      workflow_keys = Sidekiq.redis { |r| r.keys('gush.workflows.*') }

      workflow_keys.map do |workflow_key|
        workflow_id = workflow_key.split('.')[-1]

        begin
          new(Gush::Workflow.find(workflow_id))
        rescue
          nil
        end
      end.compact
    end

    private
    def total_jobs_count
      workflow.jobs.count
    end

    def failed_jobs_count
      workflow.jobs.count(&:failed?).to_s
    end

    def succeeded_jobs_count
      workflow.jobs.count(&:succeeded?).to_s
    end

    def enqueued_jobs_count
      workflow.jobs.count(&:enqueued?).to_s
    end

    def running_jobs_count
      workflow.jobs.count(&:running?).to_s
    end

    def remaining_jobs_count
      workflow.jobs.count{|j| [j.finished?, j.failed?, j.enqueued?].none? }.to_s
    end

    def running_status
      finished = succeeded_jobs_count.to_i
      status = "running"
      status += "<br />#{finished}/#{total_jobs_count} [#{(finished*100)/total_jobs_count}%]"
    end

    def failed_status
      status = "failed"
      status += "<br />#{failed_job} failed"
    end

    def failed_job
      workflow.jobs.find(&:failed?).name
    end
  end
end
