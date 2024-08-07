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
        dependencies = workflow.dependencies

        expect(workflow.id).to eq(expected_workflow.id)
        expect(workflow.persisted).to eq(true)
        expect(workflow.jobs.map(&:name)).to match_array(expected_workflow.jobs.map(&:name))
        expect(workflow.dependencies).to eq(dependencies)
      end

      context "when workflow has parameters" do
        it "returns Workflow object" do
          expected_workflow = ParameterTestWorkflow.create(true, kwarg: 123)
          workflow = client.find_workflow(expected_workflow.id)

          expect(workflow.id).to eq(expected_workflow.id)
          expect(workflow.arguments).to eq([true])
          expect(workflow.kwargs).to eq({ kwarg: 123 })
          expect(workflow.jobs.map(&:name)).to match_array(expected_workflow.jobs.map(&:name))
        end
      end

      context "when workflow has globals" do
        it "returns Workflow object" do
          expected_workflow = TestWorkflow.create(globals: { global1: 'foo' })
          workflow = client.find_workflow(expected_workflow.id)

          expect(workflow.id).to eq(expected_workflow.id)
          expect(workflow.globals[:global1]).to eq('foo')
        end
      end
    end
  end

  describe "#start_workflow" do
    context "when there is wait parameter configured" do
      let(:freeze_time) { Time.utc(2023, 01, 21, 14, 36, 0) }

      it "schedules job execution" do
        travel_to freeze_time do
          workflow = WaitableTestWorkflow.create
          client.start_workflow(workflow)
          expect(Gush::Worker).to have_a_job_enqueued_at(workflow.id, job_with_id("Prepare"), 5.minutes)
        end
      end
    end

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

  describe "#next_free_job_id" do
    it "returns an id" do
      expect(client.next_free_job_id('123', Prepare.to_s)).to match(/^\h{8}-\h{4}-(\h{4})-\h{4}-\h{12}$/)
    end

    it "returns an id that doesn't match an existing job id" do
      workflow = TestWorkflow.create
      job = workflow.jobs.first

      second_try_id = '1234'
      allow(SecureRandom).to receive(:uuid).and_return(job.id, second_try_id)

      expect(client.next_free_job_id(workflow.id, job.class.to_s)).to eq(second_try_id)
    end
  end

  describe "#next_free_workflow_id" do
    it "returns an id" do
      expect(client.next_free_workflow_id).to match(/^\h{8}-\h{4}-(\h{4})-\h{4}-\h{12}$/)
    end

    it "returns an id that doesn't match an existing workflow id" do
      workflow = TestWorkflow.create

      second_try_id = '1234'
      allow(SecureRandom).to receive(:uuid).and_return(workflow.id, second_try_id)

      expect(client.next_free_workflow_id).to eq(second_try_id)
    end
  end

  describe "#persist_workflow" do
    it "persists JSON dump of the Workflow and its jobs" do
      job = double("job", to_json: 'json')
      workflow = double("workflow", id: 'abcd', jobs: [job, job, job], to_json: '"json"')
      expect(client).to receive(:persist_job).exactly(3).times.with(workflow.id, job)
      expect(workflow).to receive(:mark_as_persisted)
      client.persist_workflow(workflow)
      expect(redis.keys("gush.workflows.abcd").length).to eq(1)
    end
  end

  describe "#destroy_workflow" do
    it "removes all Redis keys related to the workflow" do
      workflow = TestWorkflow.create
      expect(redis.keys("gush.workflows.#{workflow.id}").length).to eq(1)
      expect(redis.keys("gush.jobs.#{workflow.id}.*").length).to eq(5)

      client.destroy_workflow(workflow)

      expect(redis.keys("gush.workflows.#{workflow.id}").length).to eq(0)
      expect(redis.keys("gush.jobs.#{workflow.id}.*").length).to eq(0)
    end
  end

  describe "#expire_workflow" do
    let(:ttl) { 2000 }

    it "sets TTL for all Redis keys related to the workflow" do
      workflow = TestWorkflow.create

      client.expire_workflow(workflow, ttl)

      expect(redis.ttl("gush.workflows.#{workflow.id}")).to eq(ttl)

      workflow.jobs.each do |job|
        expect(redis.ttl("gush.jobs.#{workflow.id}.#{job.klass}")).to eq(ttl)
      end
    end
  end

  describe "#persist_job" do
    it "persists JSON dump of the job in Redis" do

      job = BobJob.new(name: 'bob', id: 'abcd123')

      client.persist_job('deadbeef', job)
      expect(redis.keys("gush.jobs.deadbeef.*").length).to eq(1)
    end
  end

  describe "#all_workflows" do
    it "returns all registered workflows" do
      workflow = TestWorkflow.create
      workflows = client.all_workflows
      expect(workflows.map(&:id)).to eq([workflow.id])
    end
  end

  it "should be able to handle outdated data format" do
    workflow = TestWorkflow.create

    # malform the data
    hash = Gush::JSON.decode(redis.get("gush.workflows.#{workflow.id}"), symbolize_keys: true)
    hash.delete(:stopped)
    redis.set("gush.workflows.#{workflow.id}", Gush::JSON.encode(hash))

    expect {
      workflow = client.find_workflow(workflow.id)
      expect(workflow.stopped?).to be false
    }.not_to raise_error
  end
end
