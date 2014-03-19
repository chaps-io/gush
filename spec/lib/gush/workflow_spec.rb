require 'spec_helper'

describe Gush::Workflow do
  subject { TestWorkflow.new("test-workflow") }

  describe "#initialize" do
    context "when configure option is true" do
      it "runs #configure method " do
        expect_any_instance_of(TestWorkflow).to receive(:configure)
        TestWorkflow.new("name", configure: true)
      end
    end
  end

  describe "#to_json" do
    it "returns correct hash" do
      klass = Class.new(Gush::Workflow) do
        def configure
          run Gush::Job
        end
      end
      result = JSON.parse(klass.new("workflow").to_json)
      expected = {
        "name"=>"workflow",
        "json_class"=>nil,
        "children"=>[
          {
            "name"=>"Gush::Job",
            "json_class"=>"Gush::Job",
            "finished"=>false,
            "enqueued"=>false,
            "failed"=>false
          }
        ]
      }
      expect(result).to eq(expected)
    end
  end

  describe "#find_job" do
    it "finds job by its name" do
      expect(TestWorkflow.new("test").find_job("PersistAllJob")).to be_instance_of(PersistAllJob)
    end
  end

  describe "#run" do
    context "when tree is empty" do
      it "adds new job with the given class as a child" do
        tree = Gush::Workflow.new("workflow")
        tree.run(Gush::Job)
        expect(tree.children).to include(Gush::Job)
      end
    end

    context "when last node is a job" do
      it "attaches job as a child of the last inserted job" do
        tree = Gush::Workflow.new("workflow")
        tree.run(Gush::Job)
        tree.run(Gush::Job)
        expect(tree.children.first).to be_an_instance_of(Gush::Job)
        expect(tree.children.first.children.first).to be_an_instance_of(Gush::Job)
      end
    end

    context "when last node is a workflow" do
      it "attaches the new job to the first child of the workflow" do
        tree = Gush::Workflow.new("workflow")
        klass = Class.new(Gush::Workflow) do
          def configure
            run Gush::Job
          end
        end

        tree.run(klass)
        tree.run(Gush::Job)

        expect(tree.children.first).to be_an_instance_of(klass)
        expect(tree.children.first.children.first).to be_an_instance_of(Gush::Job)
        expect(tree.children.first.children.first.children.first).to be_an_instance_of(Gush::Job)
      end
    end
  end

  describe "#concurrently" do
    it "creates a Gush::ConcurrentWorkflow and attaches nested jobs to it" do
      tree = Gush::Workflow.new("workflow")

      tree.concurrently do
        run Gush::Job
      end

      expect(tree.children.first).to be_an_instance_of(Gush::ConcurrentWorkflow)
      expect(tree.children.first.children.first).to be_an_instance_of(Gush::Job)
    end
  end

  describe "#failed?" do
    context "when one of the jobs failed" do
      it "returns true" do
        subject.children.first.failed = true
        expect(subject.failed?).to be_true
      end
    end

    context "when no jobs failed" do
      it "returns true" do
        expect(subject.failed?).to be_false
      end
    end
  end

  describe "#running?" do
    context "when no enqueued jobs" do
      it "returns false" do
        expect(subject.running?).to be_false
      end
    end

    context "when some jobs are enqueued" do
      it "returns true" do
        subject.children.first.enqueued = true
        expect(subject.running?).to be_true
      end
    end
  end

  describe "#finished?" do
    it "returns false if any jobs are unfinished" do
      expect(subject.finished?).to be_false
    end

    it "returns true if all jobs are finished" do
      subject.select { |n| n.class <= Gush::Job }.each {|n| n.finished = true }
      expect(subject.finished?).to be_true
    end
  end

  describe "#next_jobs" do
    context "when one of the jobs failed" do
      it "returns empty array" do
        subject.children.first.finished = true
        subject.children.first.children.first.children.first.failed = true
        expect(subject.next_jobs.map(&:name)).to match_array([])
      end
    end

    it "returns next non-queued and unfinished jobs" do
      expect(subject.next_jobs.map(&:name)).to match_array(["Prepare"])
    end

    it "returns all parallel non-queued and unfinished jobs" do
      subject.children.first.finished = true
      expect(subject.next_jobs.map(&:name)).to match_array(["FetchFirstJob", "FetchSecondJob"])
    end

    it "returns empty array when there are enqueued but unfinished jobs" do
      subject.children.first.enqueued = true
      expect(subject.next_jobs).to match_array([])
    end

    it "returns only unfinished and non-queued jobs from a parallel level" do
      subject.children.first.finished = true
      subject.children.first.children.first.children.first.finished = true
      expect(subject.next_jobs.map(&:name)).to match_array(["FetchSecondJob"])
    end

    it "returns next level of unfished jobs after finished parallel level" do
      subject.children.first.finished = true
      subject.children.first.children.first.children.first.finished = true
      subject.children.first.children.first.children.last.finished = true
      expect(subject.next_jobs.map(&:name)).to match_array(["PersistAllJob"])
    end
  end
end
