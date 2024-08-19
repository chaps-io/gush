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

      context "when workflow was persisted without job_klasses" do
        it "returns Workflow object" do
          expected_workflow = TestWorkflow.create

          json = Gush::JSON.encode(expected_workflow.to_hash.except(:job_klasses))
          redis.set("gush.workflows.#{expected_workflow.id}", json)

          workflow = client.find_workflow(expected_workflow.id)

          expect(workflow.id).to eq(expected_workflow.id)
          expect(workflow.jobs.map(&:name)).to match_array(expected_workflow.jobs.map(&:name))
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
      expect(client).to receive(:persist_job).exactly(3).times.with(workflow.id, job, expires_at: nil)
      expect(workflow).to receive(:mark_as_persisted)
      client.persist_workflow(workflow)
      expect(redis.keys("gush.workflows.abcd").length).to eq(1)
    end

    it "sets created_at index" do
      workflow = double("workflow", id: 'abcd', jobs: [], to_json: '"json"')
      expect(workflow).to receive(:mark_as_persisted).twice

      freeze_time = Time.now.round # travel_to doesn't support fractions of a second
      travel_to(freeze_time) do
        client.persist_workflow(workflow)
      end

      expect(redis.zrange("gush.idx.workflows.created_at", 0, -1, with_scores: true))
        .to eq([[workflow.id, freeze_time.to_f]])

      # Persisting the workflow again should not affect its created_at index score
      client.persist_workflow(workflow)
      expect(redis.zrange("gush.idx.workflows.created_at", 0, -1, with_scores: true))
        .to eq([[workflow.id, freeze_time.to_f]])
    end

    it "sets expires_at index when there is a ttl configured" do
      allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

      workflow = double("workflow", id: 'abcd', jobs: [], to_json: '"json"')
      expect(workflow).to receive(:mark_as_persisted).twice

      freeze_time = Time.now.round # travel_to doesn't support fractions of a second
      travel_to(freeze_time) do
        client.persist_workflow(workflow)
      end

      expires_at = freeze_time + 1000
      expect(redis.zrange("gush.idx.workflows.expires_at", 0, -1, with_scores: true))
        .to eq([[workflow.id, expires_at.to_f]])

      # Persisting the workflow again should not affect its expires_at index score
      client.persist_workflow(workflow)
      expect(redis.zrange("gush.idx.workflows.expires_at", 0, -1, with_scores: true))
        .to eq([[workflow.id, expires_at.to_f]])
    end

    it "does not set expires_at index when there is no ttl configured" do
      workflow = double("workflow", id: 'abcd', jobs: [], to_json: '"json"')
      expect(workflow).to receive(:mark_as_persisted)
      client.persist_workflow(workflow)

      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(0)
    end

    it "does not set expires_at index when updating a pre-existing workflow without a ttl" do
      allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

      workflow = double("workflow", id: 'abcd', jobs: [], to_json: '"json"')
      expect(workflow).to receive(:mark_as_persisted).twice

      client.persist_workflow(workflow)

      client.expire_workflow(workflow, -1)
      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(0)

      client.persist_workflow(workflow)
      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(0)
    end

    it "does not change expires_at index when updating a pre-existing workflow with a non-standard ttl" do
      allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

      workflow = double("workflow", id: 'abcd', jobs: [], to_json: '"json"')
      expect(workflow).to receive(:mark_as_persisted).twice

      freeze_time = Time.now.round # travel_to doesn't support fractions of a second
      travel_to(freeze_time) do
        client.persist_workflow(workflow)

        expires_at = freeze_time.to_i + 1234
        client.expire_workflow(workflow, 1234)
        expect(redis.zscore("gush.idx.workflows.expires_at", workflow.id)).to eq(expires_at)

        client.persist_workflow(workflow)
        expect(redis.zscore("gush.idx.workflows.expires_at", workflow.id)).to eq(expires_at)
      end
    end
  end

  describe "#destroy_workflow" do
    it "removes all Redis keys related to the workflow" do
      allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

      workflow = TestWorkflow.create
      expect(redis.keys("gush.workflows.#{workflow.id}").length).to eq(1)
      expect(redis.keys("gush.jobs.#{workflow.id}.*").length).to eq(5)
      expect(redis.zcard("gush.idx.workflows.created_at")).to eq(1)
      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(1)
      expect(redis.zcard("gush.idx.jobs.expires_at")).to eq(5)

      client.destroy_workflow(workflow)

      expect(redis.keys("gush.workflows.#{workflow.id}").length).to eq(0)
      expect(redis.keys("gush.jobs.#{workflow.id}.*").length).to eq(0)
      expect(redis.zcard("gush.idx.workflows.created_at")).to eq(0)
      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(0)
      expect(redis.zcard("gush.idx.jobs.expires_at")).to eq(0)
    end
  end

  describe "#expire_workflows" do
    it "removes auto-expired workflows" do
      allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

      workflow = TestWorkflow.create

      # before workflow's expiration time
      client.expire_workflows

      expect(redis.keys("gush.workflows.*").length).to eq(1)

      # after workflow's expiration time
      client.expire_workflows(Time.now.to_f + 1001)

      expect(redis.keys("gush.workflows.#{workflow.id}").length).to eq(0)
      expect(redis.keys("gush.jobs.#{workflow.id}.*").length).to eq(0)
      expect(redis.zcard("gush.idx.workflows.created_at")).to eq(0)
      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(0)
      expect(redis.zcard("gush.idx.jobs.expires_at")).to eq(0)
    end

    it "removes manually-expired workflows" do
      workflow = TestWorkflow.create

      # workflow hasn't been expired
      client.expire_workflows(Time.now.to_f + 100_000)

      expect(redis.keys("gush.workflows.*").length).to eq(1)

      client.expire_workflow(workflow, 10)

      # after workflow's expiration time
      client.expire_workflows(Time.now.to_f + 20)

      expect(redis.keys("gush.workflows.#{workflow.id}").length).to eq(0)
      expect(redis.keys("gush.jobs.#{workflow.id}.*").length).to eq(0)
      expect(redis.zcard("gush.idx.workflows.created_at")).to eq(0)
      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(0)
      expect(redis.zcard("gush.idx.jobs.expires_at")).to eq(0)
    end
  end

  describe "#expire_workflow" do
    let(:ttl) { 2000 }

    it "sets an expiration time for the workflow" do
      workflow = TestWorkflow.create

      freeze_time = Time.now.round # travel_to doesn't support fractions of a second
      expires_at = freeze_time.to_f + ttl
      travel_to(freeze_time) do
        client.expire_workflow(workflow, ttl)
      end

      expect(redis.zscore("gush.idx.workflows.expires_at", workflow.id)).to eq(expires_at)

      workflow.jobs.each do |job|
        expect(redis.zscore("gush.idx.jobs.expires_at", "#{workflow.id}.#{job.klass}")).to eq(expires_at)
      end
    end

    it "clears an expiration time for the workflow when given -1" do
      workflow = TestWorkflow.create

      client.expire_workflow(workflow, 100)
      expect(redis.zscore("gush.idx.workflows.expires_at", workflow.id)).to be > 0

      client.expire_workflow(workflow, -1)
      expect(redis.zscore("gush.idx.workflows.expires_at", workflow.id)).to eq(nil)

      workflow.jobs.each do |job|
        expect(redis.zscore("gush.idx.jobs.expires_at", "#{workflow.id}.#{job.klass}")).to eq(nil)
      end
    end
  end

  describe "#persist_job" do
    it "persists JSON dump of the job in Redis" do

      job = BobJob.new(name: 'bob', id: 'abcd123')

      client.persist_job('deadbeef', job)
      expect(redis.keys("gush.jobs.deadbeef.*").length).to eq(1)
    end

    it "sets expires_at index when expires_at is provided" do
      job = BobJob.new(name: 'bob', id: 'abcd123')

      freeze_time = Time.now.round # travel_to doesn't support fractions of a second
      expires_at = freeze_time.to_f + 1000

      travel_to(freeze_time) do
        client.persist_job('deadbeef', job, expires_at: expires_at)
      end

      expect(redis.zrange("gush.idx.jobs.expires_at", 0, -1, with_scores: true))
        .to eq([["deadbeef.#{job.klass}", expires_at]])

      # Persisting the workflow again should not affect its expires_at index score
      client.persist_job('deadbeef', job)
      expect(redis.zrange("gush.idx.jobs.expires_at", 0, -1, with_scores: true))
        .to eq([["deadbeef.#{job.klass}", expires_at]])
    end

    it "does not set expires_at index when there is no ttl configured" do
      job = BobJob.new(name: 'bob', id: 'abcd123')
      client.persist_job('deadbeef', job)

      expect(redis.zcard("gush.idx.jobs.expires_at")).to eq(0)
    end
  end

  describe "#workflow_ids" do
    it "returns a page of registered workflow ids" do
      workflow = TestWorkflow.create
      ids = client.workflow_ids
      expect(ids).to eq([workflow.id])
    end

    it "sorts workflow ids by created time or reverse created time" do
      ids = 3.times.map { TestWorkflow.create }.map(&:id)

      expect(client.workflow_ids).to eq(ids)
      expect(client.workflow_ids(order: :asc)).to eq(ids)
      expect(client.workflow_ids(order: :desc)).to eq(ids.reverse)
    end

    it "supports start and stop params" do
      ids = 3.times.map { TestWorkflow.create }.map(&:id)

      expect(client.workflow_ids(0, 1)).to eq(ids.slice(0..1))
      expect(client.workflow_ids(1, 1)).to eq(ids.slice(1..1))
      expect(client.workflow_ids(1, 10)).to eq(ids.slice(1..2))
      expect(client.workflow_ids(0, -1)).to eq(ids)
    end

    it "supports start and stop params using created timestamps" do
      times = [100, 200, 300]
      ids = []

      times.each do |t|
        travel_to Time.at(t) do
          ids << TestWorkflow.create.id
        end
      end

      expect(client.workflow_ids(0, 1, by_ts: true)).to be_empty
      expect(client.workflow_ids(50, 150, by_ts: true)).to eq(ids.slice(0..0))
      expect(client.workflow_ids(150, 50, by_ts: true, order: :desc)).to eq(ids.slice(0..0))
      expect(client.workflow_ids("-inf", "inf", by_ts: true)).to eq(ids)
    end
  end

  describe "#workflows" do
    it "returns a page of registered workflows" do
      workflow = TestWorkflow.create
      expect(client.workflows.map(&:id)).to eq([workflow.id])
    end
  end

  describe "#workflows_count" do
    it "returns a count of registered workflows" do
      allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

      expect(client.workflows_count).to eq(0)

      workflow = TestWorkflow.create
      expect(client.workflows_count).to eq(1)

      client.expire_workflows(Time.now.to_f + 1001)
      expect(client.workflows_count).to eq(0)
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
