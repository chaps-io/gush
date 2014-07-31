require 'spec_helper'

describe Gush::Worker do
  let(:workflow_id) { '1234'                        }
  let(:workflow)    { TestWorkflow.new(workflow_id) }
  let(:job)         { workflow.find_job("Prepare")  }
  let(:config)      { :fake_config                  }

  before :each do
    allow(Gush).to receive(:find_workflow).with(workflow_id).and_return(workflow)
  end

  describe "#perform" do
    context "when job fails" do
      before :each do
        expect(job).to receive(:work).and_raise(StandardError)
      end

      it "should mark it as failed" do
        expect(Gush).to receive(:persist_job).with(workflow_id, job) do |_, job|
          expect(job).to be_failed
        end

        Gush::Worker.new.perform(workflow_id, "Prepare", config)
      end

      it "reports that job failed" do
        allow(Gush).to receive(:worker_report)
        Gush::Worker.new.perform(workflow_id, "Prepare", config)
        expect(Gush).to have_received(:worker_report).with(hash_including(status: :failed))
      end
    end

    context "when job completes successfully" do
      it "should mark it as succedeed" do
        allow(Gush).to receive(:persist_job)

        Gush::Worker.new.perform(workflow_id, "Prepare", config)

        expect(Gush).to have_received(:persist_job).at_least(1).times.with(workflow_id, job) do |_, job|
          expect(job).to be_succeeded
        end
      end

      it "reports that job succedeed" do
        allow(Gush).to receive(:worker_report)
        Gush::Worker.new.perform(workflow_id, "Prepare", config)

        expect(Gush).to have_received(:worker_report).with(hash_including(status: :finished))
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
      job.enqueue!
      expect(job.logger).to be_a TestLogger
    end

    it "reports when the job is started" do
      allow(Gush).to receive(:worker_report)
      Gush::Worker.new.perform(workflow_id, "Prepare", config)
      expect(Gush).to have_received(:worker_report).with(hash_including(status: :started))
    end
  end
end
