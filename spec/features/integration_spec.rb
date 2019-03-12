require 'spec_helper'
require 'pry'

describe "Workflows" do
  context "when all jobs finish successfuly" do
    it "marks workflow as completed" do
      flow = TestWorkflow.create
      perform_enqueued_jobs do
        flow.start!
      end

      flow = flow.reload
      expect(flow).to be_finished
      expect(flow).to_not be_failed
    end
  end

  context 'when one of the jobs fails initally' do
    it 'succeeds when the job retries' do
      FAIL_THEN_SUCCEED_SPY = double()
      allow(FAIL_THEN_SUCCEED_SPY).to receive(:foo).and_return('failure', 'success')

      class FailsThenSucceeds < Gush::Job
        def perform
          if FAIL_THEN_SUCCEED_SPY.foo == 'failure'
            raise NameError
          end
        end
      end

      class SecondChanceWorkflow < Gush::Workflow
        def configure
          run Prepare
          run FailsThenSucceeds, after: Prepare
          run NormalizeJob, after: FailsThenSucceeds
        end
      end

      flow = SecondChanceWorkflow.create
      flow.start!

      expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(['Prepare']))
      perform_one

      expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(['FailsThenSucceeds']))
      expect do
        perform_one
      end.to raise_error(NameError)

      expect(flow.reload).to be_failed
      expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(['FailsThenSucceeds']))

      # Retry the same job again, but this time succeeds
      perform_one

      expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(['NormalizeJob']))
      perform_one

      flow = flow.reload
      expect(flow).to be_finished
      expect(flow).to_not be_failed
    end
  end

  it "runs the whole workflow in proper order" do
    flow = TestWorkflow.create
    flow.start!

    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(['Prepare']))

    perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["FetchFirstJob", "FetchSecondJob"]))

    perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["FetchSecondJob", "PersistFirstJob"]))

    perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["PersistFirstJob"]))

    perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["NormalizeJob"]))

    perform_one

    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
  end

  it "passes payloads down the workflow" do
    class UpcaseJob < Gush::Job
      def perform
        output params[:input].upcase
      end
    end

    class PrefixJob < Gush::Job
      def perform
        output params[:prefix].capitalize
      end
    end

    class PrependJob < Gush::Job
      def perform
        string = "#{payloads.find { |j| j[:class] == 'PrefixJob'}[:output]}: #{payloads.find { |j| j[:class] == 'UpcaseJob'}[:output]}"
        output string
      end
    end

    class PayloadWorkflow < Gush::Workflow
      def configure
        run UpcaseJob, params: {input: "some text"}
        run PrefixJob, params: {prefix: "a prefix"}
        run PrependJob, after: [UpcaseJob, PrefixJob]
      end
    end

    flow = PayloadWorkflow.create
    flow.start!

    perform_one
    expect(flow.reload.find_job("UpcaseJob").output_payload).to eq("SOME TEXT")

    perform_one
    expect(flow.reload.find_job("PrefixJob").output_payload).to eq("A prefix")

    perform_one
    expect(flow.reload.find_job("PrependJob").output_payload).to eq("A prefix: SOME TEXT")
  end

  it "passes payloads from workflow that runs multiple same class jobs with nameized payloads" do
    class RepetitiveJob < Gush::Job
      def perform
        output params[:input]
      end
    end

    class SummaryJob < Gush::Job
      def perform
        output payloads.map { |payload| payload[:output] }
      end
    end

    class PayloadWorkflow < Gush::Workflow
      def configure
        jobs = []
        jobs << run(RepetitiveJob, params: {input: 'first'})
        jobs << run(RepetitiveJob, params: {input: 'second'})
        jobs << run(RepetitiveJob, params: {input: 'third'})
        run SummaryJob, after: jobs
      end
    end

    flow = PayloadWorkflow.create
    flow.start!

    perform_one
    expect(flow.reload.find_job(flow.jobs[0].name).output_payload).to eq('first')

    perform_one
    expect(flow.reload.find_job(flow.jobs[1].name).output_payload).to eq('second')

    perform_one
    expect(flow.reload.find_job(flow.jobs[2].name).output_payload).to eq('third')

    perform_one
    expect(flow.reload.find_job(flow.jobs[3].name).output_payload).to eq(%w(first second third))
  end

  it "does not execute `configure` on each job for huge workflows" do
    INTERNAL_SPY = double('spy')
    INTERNAL_CONFIGURE_SPY = double('configure spy')
    expect(INTERNAL_SPY).to receive(:some_method).exactly(110).times

    # One time when persisting, second time when reloading in the spec
    expect(INTERNAL_CONFIGURE_SPY).to receive(:some_method).exactly(2).times

    class SimpleJob < Gush::Job
      def perform
        INTERNAL_SPY.some_method
      end
    end

    class GiganticWorkflow < Gush::Workflow
      def configure
        INTERNAL_CONFIGURE_SPY.some_method

        10.times do
          main = run(SimpleJob)
          10.times do
            run(SimpleJob, after: main)
          end
        end
      end
    end

    flow = GiganticWorkflow.create
    flow.start!

    110.times do
      perform_one
    end

    flow = flow.reload
    expect(flow).to be_finished
    expect(flow).to_not be_failed
  end

  it 'executes job with multiple ancestors only once' do
    NO_DUPS_INTERNAL_SPY = double('spy')
    expect(NO_DUPS_INTERNAL_SPY).to receive(:some_method).exactly(1).times

    class FirstAncestor < Gush::Job
      def perform
      end
    end

    class SecondAncestor < Gush::Job
      def perform
      end
    end

    class FinalJob < Gush::Job
      def perform
        NO_DUPS_INTERNAL_SPY.some_method
      end
    end

    class NoDuplicatesWorkflow < Gush::Workflow
      def configure
        run FirstAncestor
        run SecondAncestor

        run FinalJob, after: [FirstAncestor, SecondAncestor]
      end
    end

    flow = NoDuplicatesWorkflow.create
    flow.start!

    5.times do
      perform_one
    end

    flow = flow.reload
    expect(flow).to be_finished
    expect(flow).to_not be_failed
  end
end
