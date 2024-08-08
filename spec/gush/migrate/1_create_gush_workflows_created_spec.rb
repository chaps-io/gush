require 'spec_helper'
require 'gush/migrate/1_create_gush_workflows_created'

describe Gush::IndexWorkflowsByCreatedAtAndExpiresAt do

  describe "#up" do
    it "adds existing workflows to created_at index, but not expires_at index" do
      TestWorkflow.create
      redis.del("gush.idx.workflows.created_at")

      allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

      subject.migrate

      expect(redis.zcard("gush.idx.workflows.created_at")).to eq(1)
      expect(redis.zcard("gush.idx.workflows.expires_at")).to eq(0)
      expect(redis.zcard("gush.idx.jobs.expires_at")).to eq(0)
    end

    it "adds expiring workflows to expires_at index" do
      workflow = TestWorkflow.create
      redis.del("gush.idx.workflows.created_at")

      freeze_time = Time.now.round # travel_to doesn't support fractions of a second
      travel_to(freeze_time) do
        redis.expire("gush.workflows.#{workflow.id}", 1234)
        expires_at = freeze_time.to_f + 1234

        allow_any_instance_of(Gush::Configuration).to receive(:ttl).and_return(1000)

        subject.migrate

        expect(redis.ttl("gush.workflows.#{workflow.id}")).to eq(-1)
        expect(redis.ttl("gush.jobs.#{workflow.id}.#{workflow.jobs.first.class.name}")).to eq(-1)

        expect(redis.zrange("gush.idx.workflows.expires_at", 0, -1, with_scores: true))
          .to eq([[workflow.id, expires_at]])
        expect(redis.zcard("gush.idx.jobs.expires_at")).to eq(5)
      end
    end
  end
end
