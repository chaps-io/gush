require 'spec_helper'

describe "Workflows" do
  context "when all jobs finish successfuly" do
    it "marks workflow as completed" do
      flow = TestWorkflow.create
      flow.start!
      expect(flow.reload).to be_running

      Gush::Worker.drain

      flow = flow.reload
      expect(flow).to be_finished
      expect(flow).to_not be_failed
    end
  end

  it "runs the whole workflow in proper order" do
    flow = TestWorkflow.create
    flow.start!

    expect(Gush::Worker).to have_jobs(flow.id, ["Prepare"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["FetchFirstJob", "FetchSecondJob"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["FetchSecondJob", "PersistFirstJob"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["PersistFirstJob", "NormalizeJob"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["NormalizeJob"])

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
        string = "#{payloads["PrefixJob"]}: #{payloads["UpcaseJob"]}"
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
end
