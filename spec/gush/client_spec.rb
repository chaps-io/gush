require 'spec_helper'

describe Gush::Client do
  let(:client) do
    Gush::Client.new(Gush::Configuration.new(gushfile: GUSHFILE, redis_url: REDIS_URL))
  end

  describe "#find_workflow" do
    context "when workflow doesn't exist" do
      it "returns raises WorkflowNotFound" do
        expect {
          client.find_workflow('nope')
        }.to raise_error(Gush::WorkflowNotFound)
      end
    end

    context "when given workflow exists" do
      it "returns Workflow object" do
        expected_workflow = TestWorkflow.create
        workflow = client.find_workflow(expected_workflow.id)

        expect(workflow.id).to eq(expected_workflow.id)
        expect(workflow.jobs.map(&:id)).to match_array(expected_workflow.jobs.map(&:id))
      end

      context "when workflow has parameters" do
        it "returns Workflow object" do
          expected_workflow = ParameterTestWorkflow.create(true)
          workflow = client.find_workflow(expected_workflow.id)

          expect(workflow.id).to eq(expected_workflow.id)
          expect(workflow.jobs.map(&:id)).to match_array(expected_workflow.jobs.map(&:id))
        end
      end
    end
  end

  describe "#start_workflow" do
    it "enqueues next jobs from the workflow" do
      workflow = TestWorkflow.create
      expect {
        client.start_workflow(workflow)
      }.to change{ActiveJob::Base.queue_adapter.enqueued_jobs.size}.from(0).to(1)
    end

    it "removes stopped flag when the workflow is started" do
      workflow = TestWorkflow.create
      workflow.mark_as_stopped
      workflow.persist!
      expect {
        client.start_workflow(workflow)
      }.to change{client.find_workflow(workflow.id).stopped?}.from(true).to(false)
    end

    it "marks the enqueued jobs as enqueued" do
      workflow = TestWorkflow.create
      client.start_workflow(workflow)
      job = workflow.reload.find_job("Prepare")
      expect(job.enqueued?).to eq(true)
    end
  end

  describe "#stop_workflow" do
    it "marks the workflow as stopped" do
      workflow = TestWorkflow.create
      expect {
        client.stop_workflow(workflow.id)

      }.to change{client.find_workflow(workflow.id).stopped?}.from(false).to(true)
    end
  end

  describe "#persist_workflow" do
    it "persists Workflow and its jobs with relationships" do
      workflow = TestWorkflow.new
      client.persist_workflow(workflow)

      persisted_workflow = client.find_workflow(workflow.id)
      expect(persisted_workflow).to be_present
    end
  end

  describe "#destroy_workflow" do
    it "removes all Redis keys related to the workflow" do
      workflow = TestWorkflow.create
      expect(client.find_workflow(workflow.id)).to be_present

      client.destroy_workflow(workflow)

      expect do
        client.find_workflow(workflow.id)
      end.to raise_error(Gush::WorkflowNotFound)
    end
  end

  describe "#persist_job" do
    it "persists JSON dump of the job in Redis" do

      job = BobJob.new(id: SecureRandom.uuid)

      client.persist_job('deadbeef', job)
      expect(client.find_job('deadbeef', job.id)).to be_present
    end
  end

  describe "#all_workflows" do
    it "returns all registered workflows" do
      workflow = TestWorkflow.create
      workflows = client.all_workflows
      expect(workflows.map(&:id)).to eq([workflow.id])
    end
  end
end
