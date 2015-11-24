require 'spec_helper'

describe "Workflows" do
  context "when all jobs finish successfuly" do
    it "marks workflow as completed" do
      flow = TestWorkflow.create
      flow.start!

      Gush::Worker.drain

      flow = flow.reload
      expect(flow).to be_finished
      expect(flow).to_not be_failed
    end
  end

  it "runs the whole workflow in proper order" do
    flow = TestWorkflow.create
    flow.start!

    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(['Prepare']))

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["FetchFirstJob", "FetchSecondJob"]))

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["FetchSecondJob", "PersistFirstJob"]))

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["PersistFirstJob"]))

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, jobs_with_id(["NormalizeJob"]))

    Gush::Worker.perform_one

    expect(Gush::Worker.jobs).to be_empty
  end

  it "passes payloads down the workflow" do
    class UpcaseJob < Gush::Job
      def work
        output params[:input].upcase
      end
    end

    class PrefixJob < Gush::Job
      def work
        output params[:prefix].capitalize
      end
    end

    class PrependJob < Gush::Job
      def work
        string = "#{payloads['PrefixJob'].first}: #{payloads['UpcaseJob'].first}"
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

    Gush::Worker.perform_one
    expect(flow.reload.find_job("UpcaseJob").output_payload).to eq("SOME TEXT")

    Gush::Worker.perform_one
    expect(flow.reload.find_job("PrefixJob").output_payload).to eq("A prefix")

    Gush::Worker.perform_one
    expect(flow.reload.find_job("PrependJob").output_payload).to eq("A prefix: SOME TEXT")


  end

  it "passes payloads from workflow that runs multiple same class jobs with nameized payloads" do
    class RepetitiveJob < Gush::Job
      def work
        output params[:input]
      end
    end

    class SummaryJob < Gush::Job
      def work
        output payloads['RepetitiveJob']
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

    Gush::Worker.perform_one
    expect(flow.reload.find_job(flow.jobs[0].name).output_payload).to eq('first')

    Gush::Worker.perform_one
    expect(flow.reload.find_job(flow.jobs[1].name).output_payload).to eq('second')

    Gush::Worker.perform_one
    expect(flow.reload.find_job(flow.jobs[2].name).output_payload).to eq('third')

    Gush::Worker.perform_one
    expect(flow.reload.find_job(flow.jobs[3].name).output_payload).to eq(%w(first second third))

  end
end
