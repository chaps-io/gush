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
end
