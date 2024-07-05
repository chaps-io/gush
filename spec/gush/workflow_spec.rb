require 'spec_helper'

describe Gush::Workflow do
  subject { TestWorkflow.create }

  describe "#initialize" do
    it "passes constructor arguments to the method" do
      klass = Class.new(Gush::Workflow) do
        def configure(*args)
          run FetchFirstJob
          run PersistFirstJob, after: FetchFirstJob
        end
      end

      expect_any_instance_of(klass).to receive(:configure).with("arg1", "arg2")
      klass.new("arg1", "arg2")
    end
  end

  describe "#status" do
    context "when failed" do
      it "returns :failed" do
        flow = TestWorkflow.create
        flow.find_job("Prepare").fail!
        flow.persist!
        expect(flow.reload.status).to eq(:failed)
      end
    end
  end

  describe "#save" do
    context "workflow not persisted" do
      it "sets persisted to true" do
        flow = TestWorkflow.new
        flow.save
        expect(flow.persisted).to be(true)
      end

      it "assigns new unique id" do
        flow = TestWorkflow.new
        flow.save
        expect(flow.id).to_not be_nil
      end
    end

    context "workflow persisted" do
      it "does not assign new id" do
        flow = TestWorkflow.new
        flow.save
        id = flow.id
        flow.save
        expect(flow.id).to eq(id)
      end
    end
  end

  describe "#continue" do
    it "enqueues failed jobs" do
      flow = TestWorkflow.create
      flow.find_job('Prepare').fail!

      expect(flow.jobs.select(&:failed?)).not_to be_empty

      flow.continue

      expect(flow.jobs.select(&:failed?)).to be_empty
      expect(flow.find_job('Prepare').failed_at).to be_nil
    end
  end

  describe "#mark_as_stopped" do
    it "marks workflow as stopped" do
      expect{ subject.mark_as_stopped }.to change{subject.stopped?}.from(false).to(true)
    end
  end

  describe "#mark_as_started" do
    it "removes stopped flag" do
      subject.stopped = true
      expect{ subject.mark_as_started }.to change{subject.stopped?}.from(true).to(false)
    end
  end

  describe "#to_json" do
    it "returns correct hash" do
      klass = Class.new(Gush::Workflow) do
        def configure(*args)
          run FetchFirstJob
          run PersistFirstJob, after: FetchFirstJob
        end
      end

      result = JSON.parse(klass.create("arg1", "arg2").to_json)
      expected = {
          "id" => an_instance_of(String),
          "name" => klass.to_s,
          "klass" => klass.to_s,
          "status" => "running",
          "total" => 2,
          "finished" => 0,
          "started_at" => nil,
          "finished_at" => nil,
          "stopped" => false,
          "arguments" => ["arg1", "arg2"]
      }
      expect(result).to match(expected)
    end
  end

  describe "#find_job" do
    it "finds job by its name" do
      expect(TestWorkflow.create.find_job("PersistFirstJob")).to be_instance_of(PersistFirstJob)
    end
  end

  describe "#run" do
    it "allows passing additional params to the job" do
      flow = Gush::Workflow.new
      flow.run(Gush::Job, params: { something: 1 })
      flow.save
      expect(flow.jobs.first.params).to eq ({ something: 1 })
    end

    it "allows passing wait param to the job" do
      flow = Gush::Workflow.new
      flow.run(Gush::Job, wait: 5.seconds)
      flow.save
      expect(flow.jobs.first.wait).to eq (5.seconds)
    end

    it "allows passing sync param to the job" do
      flow = Gush::Workflow.new
      flow.run(Gush::Job, sync: true)
      flow.save
      expect(flow.jobs.first.sync).to eq (true)
    end

    context "when graph is empty" do
      it "adds new job with the given class as a node" do
        flow = Gush::Workflow.new
        flow.run(Gush::Job)
        flow.save
        expect(flow.jobs.first).to be_instance_of(Gush::Job)
      end
    end

    it "allows `after` to accept an array of jobs" do
      tree = Gush::Workflow.new
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      klass3 = Class.new(Gush::Job)

      tree.run(klass1)
      tree.run(klass2, after: [klass1, klass3])
      tree.run(klass3)

      tree.resolve_dependencies

      expect(tree.jobs.first.outgoing).to match_array(jobs_with_id([klass2.to_s]))
    end

    it "allows `before` to accept an array of jobs" do
      tree = Gush::Workflow.new
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      klass3 = Class.new(Gush::Job)
      tree.run(klass1)
      tree.run(klass2, before: [klass1, klass3])
      tree.run(klass3)

      tree.resolve_dependencies

      expect(tree.jobs.first.incoming).to match_array(jobs_with_id([klass2.to_s]))
    end

    it "attaches job as a child of the job in `after` key" do
      tree = Gush::Workflow.new
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      tree.run(klass1)
      tree.run(klass2, after: klass1)
      tree.resolve_dependencies
      job = tree.jobs.first
      expect(job.outgoing).to match_array(jobs_with_id([klass2.to_s]))
    end

    it "attaches job as a parent of the job in `before` key" do
      tree = Gush::Workflow.new
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      tree.run(klass1)
      tree.run(klass2, before: klass1)
      tree.resolve_dependencies
      job = tree.jobs.first
      expect(job.incoming).to match_array(jobs_with_id([klass2.to_s]))
    end
  end

  describe "#failed?" do
    context "when one of the jobs failed" do
      it "returns true" do
        subject.find_job('Prepare').fail!
        expect(subject.failed?).to be_truthy
      end
    end

    context "when no jobs failed" do
      it "returns true" do
        expect(subject.failed?).to be_falsy
      end
    end
  end

  describe "#running?" do
    context "when no enqueued or running jobs" do
      it "returns false" do
        expect(subject.running?).to be_falsy
      end
    end

    context "when some jobs are running" do
      it "returns true" do
        subject.find_job('Prepare').start!
        expect(subject.running?).to be_truthy
      end
    end
  end

  describe "#finished?" do
    it "returns false if any jobs are unfinished" do
      expect(subject.finished?).to be_falsy
    end

    it "returns true if all jobs are finished" do
      subject.jobs.each {|n| n.finish! }
      expect(subject.finished?).to be_truthy
    end
  end
end
