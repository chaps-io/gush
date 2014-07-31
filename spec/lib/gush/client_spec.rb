require 'spec_helper'

describe Gush::Client do
  describe "#find_workflow" do
    context "when workflow doesn't exist" do
      it "returns raises WorkflowNotFoundError" do
        expect {
          client.find_workflow('nope')
        }.to raise_error(WorkflowNotFoundError)
      end
    end

    context "when given workflow exists" do
      it "returns Workflow object" do
        expected_workflow = TestWorkflow.new(SecureRandom.uuid)
        client.persist_workflow(expected_workflow)
        workflow = client.find_workflow(expected_workflow.id)

        expect(workflow.id).to eq(expected_workflow.id)
        expect(workflow.nodes.map(&:name)).to match_array(expected_workflow.nodes.map(&:name))
      end
    end
  end

  describe "#start_workflow" do
    it "enqueues next jobs from the workflow" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      client.persist_workflow(workflow)
      expect {
        client.start_workflow(id)
      }.to change{Gush::Worker.jobs.count}.from(0).to(1)
    end

    it "removes stopped flag when the workflow is started" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      workflow.stop!
      client.persist_workflow(workflow)
      expect {
        client.start_workflow(id)
      }.to change{client.find_workflow(id).stopped?}.from(true).to(false)
    end

    it "marks the enqueued jobs as running" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      client.persist_workflow(workflow)
      client.start_workflow(id)
      job = client.find_workflow(id).find_job("Prepare")
      expect(job.running?).to eq(true)
    end
  end

  describe "#stop_workflow" do
    it "marks the workflow as stopped" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      client.persist_workflow(workflow)
      expect {
        client.stop_workflow(id)
      }.to change{client.find_workflow(id).stopped?}.from(false).to(true)
    end
  end

  describe "#persist_workflow" do
    it "persists JSON dump of the Workflow and its jobs" do
      job = double("job", to_json: 'json')
      workflow = double("workflow", id: 'abcd', nodes: [job, job, job], to_json: '"json"')
      expect(client).to receive(:persist_job).exactly(3).times.with(workflow.id, job)
      client.persist_workflow(workflow)
      expect(redis.keys("gush.workflows.abcd").length).to eq(1)
    end
  end

  describe "#destroy_workflow" do
    it "removes all Redis keys related to the workflow" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      client.persist_workflow(workflow)
      expect(redis.keys("gush.workflows.#{id}").length).to eq(1)
      expect(redis.keys("gush.jobs.#{id}.*").length).to eq(5)

      client.destroy_workflow(workflow)

      expect(redis.keys("gush.workflows.#{id}").length).to eq(0)
      expect(redis.keys("gush.jobs.#{id}.*").length).to eq(0)
    end
  end

  describe "#persist_job" do
    it "persists JSON dump of the job in Redis" do
      job = double("job", to_json: 'json')
      client.persist_job('deadbeef', job)
      expect(redis.keys("gush.jobs.deadbeef.*").length).to eq(1)
    end
  end

  describe "#all_workflows" do
    it "returns all registered workflows" do
      workflow = TestWorkflow.new(SecureRandom.uuid)
      client.persist_workflow(workflow)
      workflows = client.all_workflows
      expect(workflows.map(&:id)).to eq([workflow.id])
    end
  end
end
