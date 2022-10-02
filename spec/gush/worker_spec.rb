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

    context "when job completes successfully" do
      it "should mark it as succedeed" do
        expect(subject).to receive(:mark_as_finished)

        subject.perform(workflow.id, "Prepare")
      end
    end

    context 'when job failed to enqueue outgoing jobs' do
      it 'enqeues another job to handling enqueue_outgoing_jobs' do
        redlock = Redlock::Client.new([Redis.new(url: REDIS_URL)])
        # allow(Redlock::Client).to receive(:new).and_return(redlock)
        fetch1 = client.find_job(workflow.id, "FetchFirstJob")
        fetch2 = client.find_job(workflow.id, "FetchSecondJob")

        lock1 = redlock.lock("gush_job_lock_#{workflow.id}-#{fetch1.name}", 2000)
        lock2 = redlock.lock("gush_job_lock_#{workflow.id}-#{fetch2.name}", 2000)

        subject.perform(workflow.id, 'Prepare')
        expect(Gush::Worker).to have_no_jobs(workflow.id, jobs_with_id(["FetchFirstJob", "FetchSecondJob"]))

        redlock.unlock(lock1)
        redlock.unlock(lock2)

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

    xit 'calls RedisMutex.with_lock with customizable locking_duration and polling_interval' do
      expect(RedisMutex).to receive(:with_lock)
        .with(anything, block: 5, sleep: 0.5).twice
      subject.perform(workflow.id, 'Prepare')
    end
  end
end
