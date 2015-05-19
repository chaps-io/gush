require 'spec_helper'

describe Gush::Workflow do
  subject { TestWorkflow.new("test-workflow") }

  describe "#initialize" do
    context "when configure option is true" do
      it "runs #configure method " do
        expect_any_instance_of(TestWorkflow).to receive(:configure)
        TestWorkflow.new(true)
      end
    end

    context "when configure option is false" do
      it "it doesn't run #configure method " do
        expect_any_instance_of(TestWorkflow).to_not receive(:configure)
        TestWorkflow.new(false)
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
        def configure
          run FetchFirstJob
          run PersistFirstJob, after: FetchFirstJob
        end
      end

      result = JSON.parse(klass.new("workflow").to_json)
      expected = {
        "name" => klass.to_s,
        "klass" => klass.to_s,
        "status" => "pending",
        "total" => 2,
        "finished" => 0,
        "started_at" => nil,
        "finished_at" => nil,
        "stopped" => false,
        "jobs" => [
          {
            "name"=>"FetchFirstJob",
            "klass"=>"FetchFirstJob",
            "finished"=>false,
            "enqueued"=>false,
            "failed"=>false,
            "incoming"=>[],
            "outgoing"=>["PersistFirstJob"],
            "finished_at"=>nil,
            "started_at"=>nil,
            "enqueued_at"=>nil,
            "failed_at"=>nil,
            "running" => false,
            "params" => {},
            "output_payload" => nil
          },
          {
            "name"=>"PersistFirstJob",
            "klass"=>"PersistFirstJob",
            "finished"=>false,
            "enqueued"=>false,
            "failed"=>false,
            "incoming"=>["FetchFirstJob"],
            "outgoing"=>[],
            "finished_at"=>nil,
            "started_at"=>nil,
            "enqueued_at"=>nil,
            "failed_at"=>nil,
            "running" => false,
            "params" => {},
            "output_payload" => nil
          }
        ]
      }
      expect(result).to include(expected)
    end
  end

  describe "#find_job" do
    it "finds job by its name" do
      expect(TestWorkflow.new("test").find_job("PersistFirstJob")).to be_instance_of(PersistFirstJob)
    end
  end

  describe "#run" do
    it "allows passing additional params to the job" do
      flow = Gush::Workflow.new("workflow")
      flow.run(Gush::Job, params: { something: 1 })
      expect(flow.jobs.first.params).to eq ({ something: 1 })
    end

    context "when graph is empty" do
      it "adds new job with the given class as a node" do
        flow = Gush::Workflow.new("workflow")
        flow.run(Gush::Job)
        expect(flow.jobs.first).to be_instance_of(Gush::Job)
      end
    end

    it "allows `after` to accept an array of jobs" do
      tree = Gush::Workflow.new("workflow")
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      klass3 = Class.new(Gush::Job)
      tree.run(klass1)
      tree.run(klass2, after: [klass1, klass3])
      tree.run(klass3)

      tree.create_dependencies

      expect(tree.jobs.first.outgoing).to match_array([klass2.to_s])
    end

    it "allows `before` to accept an array of jobs" do
      tree = Gush::Workflow.new("workflow")
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      klass3 = Class.new(Gush::Job)
      tree.run(klass1)
      tree.run(klass2, before: [klass1, klass3])
      tree.run(klass3)

      tree.create_dependencies

      expect(tree.jobs.first.incoming).to match_array([klass2.to_s])
    end

    it "attaches job as a child of the job in `after` key" do
      tree = Gush::Workflow.new("workflow")
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      tree.run(klass1)
      tree.run(klass2, after: klass1)
      tree.create_dependencies
      job = tree.jobs.first
      expect(job.outgoing).to match_array([klass2.to_s])
    end

    it "attaches job as a parent of the job in `before` key" do
      tree = Gush::Workflow.new("workflow")
      klass1 = Class.new(Gush::Job)
      klass2 = Class.new(Gush::Job)
      tree.run(klass1)
      tree.run(klass2, before: klass1)
      tree.create_dependencies
      job = tree.jobs.first
      expect(job.incoming).to match_array([klass2.to_s])
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

    context "when some jobs are enqueued" do
      it "returns true" do
        subject.find_job('Prepare').enqueue!
        expect(subject.running?).to be_truthy
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
