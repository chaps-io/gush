require 'spec_helper'

describe Gush::Worker do
  subject { described_class.new }

  let!(:workflow)   { TestWorkflow.create }
  let(:locking_duration) { 5 }
  let(:polling_interval) { 0.5 }
  let!(:job)        { client.find_job(workflow.id, "Prepare")  }
  let(:config)      { Gush.configuration.to_json  }
  let!(:client)     { Gush::Client.new }

  describe "#perform" do
    context "when job fails" do
      it "should mark it as failed" do
        class FailingJob < Gush::Job
          def perform
            invalid.code_to_raise.error
          end
        end

        class FailingWorkflow < Gush::Workflow
          def configure
            run FailingJob
          end
        end

        workflow = FailingWorkflow.create
        expect do
          subject.perform(workflow.id, "FailingJob")
        end.to raise_error(NameError)
        expect(client.find_job(workflow.id, "FailingJob")).to be_failed
      end
    end

    context "when job is skipped" do
      it "should skip the rest of the code" do
        class SkippedJob < Gush::Job
          def perform
            self.skip!
            output = "Hello"
          end
        end

        class NormalWorkflow < Gush::Workflow
          def configure
            run SkippedJob
          end
        end

        workflow = NormalWorkflow.create

        subject.perform(workflow.id, "SkippedJob")
        job = client.find_job(workflow.id, "SkippedJob")

        expect(job).to be_skipped
        expect(job).to be_finished
        expect(job.output_payload).not_to eq "Hello"
        expect(job.output_payload).to be_nil
      end
    end

    context "when job completes successfully" do
      it "should mark it as succedeed" do
        expect(subject).to receive(:mark_as_finished)

        subject.perform(workflow.id, "Prepare")
      end
    end

    context 'when job failed to enqueue outgoing jobs' do
      it 'enqeues another job to handling enqueue_outgoing_jobs' do
        allow(RedisMutex).to receive(:with_lock).and_raise(RedisMutex::LockError)
        subject.perform(workflow.id, 'Prepare')
        expect(Gush::Worker).to have_no_jobs(workflow.id, jobs_with_id(["FetchFirstJob", "FetchSecondJob"]))

        allow(RedisMutex).to receive(:with_lock).and_call_original
        perform_one
        expect(Gush::Worker).to have_jobs(workflow.id, jobs_with_id(["FetchFirstJob", "FetchSecondJob"]))
      end
    end

    it "calls job.perform method" do
      SPY = double()
      expect(SPY).to receive(:some_method)

      class OkayJob < Gush::Job
        def perform
          SPY.some_method
        end
      end

      class OkayWorkflow < Gush::Workflow
        def configure
          run OkayJob
        end
      end

      workflow = OkayWorkflow.create

      subject.perform(workflow.id, 'OkayJob')
    end

    it 'calls RedisMutex.with_lock with customizable locking_duration and polling_interval' do
      expect(RedisMutex).to receive(:with_lock)
        .with(anything, block: 5, sleep: 0.5).twice
      subject.perform(workflow.id, 'Prepare')
    end
  end
end
