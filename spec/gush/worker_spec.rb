require 'spec_helper'

describe Gush::Worker do
  subject { described_class.new }

  let!(:workflow)   { TestWorkflow.create }
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
        job_name = workflow.jobs.first.name

        expect do
          subject.perform(workflow.id, job_name)
        end.to raise_error(NameError)

        expect(client.find_job(workflow.id, job_name)).to be_failed
      end
    end

    context "when job completes successfully" do
      it "should mark it as succedeed" do
        job_name = workflow.jobs.find { |j| j.klass == Prepare }.name

        expect(subject).to receive(:mark_as_finished)

        subject.perform(workflow.id, job_name)
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
      subject.perform(workflow.id, workflow.jobs.first.name)
    end
  end
end
