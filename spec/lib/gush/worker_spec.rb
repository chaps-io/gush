require 'spec_helper'

describe Gush::Worker do
  let(:workflow_id) { '1234'                        }
  let(:workflow)    { TestWorkflow.new(workflow_id) }
  let(:job)         { workflow.find_job("Prepare")  }
  let(:config)      { client.configuration.to_json  }

  before :each do
    allow(client).to receive(:find_workflow).with(workflow_id).and_return(workflow)
    allow(Gush::Client).to receive(:new).and_return(client)
  end

  describe "#perform" do
    context "when job fails" do
      before :each do
        expect(job).to receive(:work).and_raise(StandardError)
        job.enqueue!
        job.start!
      end

      it "should mark it as failed" do
        allow(client).to receive(:persist_job)
        Gush::Worker.new.perform(workflow_id, "Prepare", config)

        expect(client).to have_received(:persist_job).with(workflow_id, job).at_least(1).times do |_, job|
          expect(job).to be_failed
        end

      end

      it "reports that job failed" do
        allow(client).to receive(:worker_report)
        Gush::Worker.new.perform(workflow_id, "Prepare", config)
        expect(client).to have_received(:worker_report).with(hash_including(status: :failed))
      end

      it "logs the exception" do
        logger = TestLogger.new(1234, 'Prepare')
        expect(logger).to receive(:<<).with(instance_of(String)).at_least(1).times
        expect(workflow).to receive(:build_logger_for_job).and_return(logger)

        Gush::Worker.new.perform(workflow_id, "Prepare", config)
      end
    end

    context "when job completes successfully" do
      it "should mark it as succedeed" do
        allow(client).to receive(:persist_job)

        Gush::Worker.new.perform(workflow_id, "Prepare", config)

        expect(client).to have_received(:persist_job).at_least(1).times.with(workflow_id, job) do |_, job|
          expect(job).to be_succeeded
        end
      end

      it "reports that job succedeed" do
        allow(client).to receive(:worker_report)
        Gush::Worker.new.perform(workflow_id, "Prepare", config)

        expect(client).to have_received(:worker_report).with(hash_including(status: :finished))
      end
    end

    [:before_work, :work, :after_work].each do |method|
      it "calls job.#{method} hook" do
        expect(job).to receive(method)
        Gush::Worker.new.perform(workflow_id, "Prepare", config)
      end
    end

    it "sets up a logger for the job" do
      Gush::Worker.new.perform(workflow_id, "Prepare", config)
      job.start!
      expect(job.logger).to be_a TestLogger
    end

    it "sets a job id" do
      job_id = 1234
      worker = Gush::Worker.new

      allow(worker).to receive(:jid).and_return(job_id)

      worker.perform(workflow_id, "Prepare", config)
      job.enqueue!
      expect(job.jid).to eq job_id
    end

    it "reports when the job is started" do
      allow(client).to receive(:worker_report)
      Gush::Worker.new.perform(workflow_id, "Prepare", config)
      expect(client).to have_received(:worker_report).with(hash_including(status: :started))
    end
  end
end
