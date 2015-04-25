require 'spec_helper'

describe Gush::Worker do
  subject { described_class.new }

  let!(:workflow)   { TestWorkflow.create }
  let(:job)         { workflow.find_job("Prepare")  }
  let(:config)      { Gush.configuration.to_json  }
  let!(:client)     { double("client") }

  before :each do
    allow(subject).to receive(:client).and_return(client)
    allow(subject).to receive(:enqueue_outgoing_jobs)

    allow(client).to receive(:find_workflow).with(workflow.id).and_return(workflow)
    expect(client).to receive(:persist_job).at_least(1).times
    expect(client).to receive(:worker_report).with(hash_including(status: :started)).ordered
  end

  describe "#perform" do
    context "when job fails" do
      it "should mark it as failed" do
        allow(job).to receive(:work).and_raise(StandardError)
        expect(client).to receive(:worker_report).with(hash_including(status: :failed)).ordered

        subject.perform(workflow.id, "Prepare", config)
        expect(workflow.find_job("Prepare")).to be_failed
      end

      it "reports that job failed" do
        allow(job).to receive(:work).and_raise(StandardError)
        expect(client).to receive(:worker_report).with(hash_including(status: :failed)).ordered

        subject.perform(workflow.id, "Prepare", config)
      end
    end

    context "when job completes successfully" do
      it "should mark it as succedeed" do
        expect(subject).to receive(:mark_as_finished)
        expect(client).to receive(:worker_report).with(hash_including(status: :finished)).ordered

        subject.perform(workflow.id, "Prepare", config)
      end

      it "reports that job succedeed" do
        expect(client).to receive(:worker_report).with(hash_including(status: :finished)).ordered

        subject.perform(workflow.id, "Prepare", config)
      end
    end

    it "calls job.work method" do
      expect(job).to receive(:work)
      expect(client).to receive(:worker_report).with(hash_including(status: :finished)).ordered

      subject.perform(workflow.id, "Prepare", config)
    end

    it "reports when the job is started" do
      allow(client).to receive(:worker_report)
      expect(client).to receive(:worker_report).with(hash_including(status: :finished)).ordered

      subject.perform(workflow.id, "Prepare", config)
    end
  end
end
