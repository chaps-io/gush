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

    it "passes constructor keyword arguments to the method" do
      klass = Class.new(Gush::Workflow) do
        def configure(*args, **kwargs)
          run FetchFirstJob
          run PersistFirstJob, after: FetchFirstJob
        end
      end

      expect_any_instance_of(klass).to receive(:configure).with("arg1", "arg2", arg3: 123)
      klass.new("arg1", "arg2", arg3: 123)
    end

    it "accepts globals" do
      flow = TestWorkflow.new(globals: { global1: 'foo' })
      expect(flow.globals[:global1]).to eq('foo')
    end

    it "accepts internal_state" do
      flow = TestWorkflow.new

      internal_state = {
        id: flow.id,
        jobs: flow.jobs,
        dependencies: flow.dependencies,
        persisted: true,
        stopped: true
      }

      flow_copy = TestWorkflow.new(internal_state: internal_state)

      expect(flow_copy.id).to eq(flow.id)
      expect(flow_copy.jobs).to eq(flow.jobs)
      expect(flow_copy.dependencies).to eq(flow.dependencies)
      expect(flow_copy.persisted).to eq(true)
      expect(flow_copy.stopped).to eq(true)
    end

    it "does not call #configure if needs_setup is false" do
      INTERNAL_SETUP_SPY = double('configure spy')
      klass = Class.new(Gush::Workflow) do
        def configure(*args)
          INTERNAL_SETUP_SPY.some_method
        end
      end

      expect(INTERNAL_SETUP_SPY).not_to receive(:some_method)

      flow = TestWorkflow.new(internal_state: { needs_setup: false })
    end
  end

  describe "#find" do
    it "fiends a workflow by id" do
      expect(Gush::Workflow.find(subject.id).id).to eq(subject.id)
    end
  end

  describe "#page" do
    it "returns a page of registered workflows" do
      flow = TestWorkflow.create
      expect(Gush::Workflow.page.map(&:id)).to eq([flow.id])
    end

    it "does not error if a stored workflow class is no longer defined in the codebase" do
      flow = TestWorkflow.create
      called = false
      allow_any_instance_of(TestWorkflow).to receive(:to_hash).and_wrap_original do |original, *args|
        called = true
        original.call(*args).merge({name: 'OldDeletedWorkflow', klass: 'OldDeletedWorkflow'})
      end
      expect {
        flow.save
        Gush::Workflow.page
      }.not_to raise_error
      expect {
        Gush::Client.new.find_workflow(flow.id)
      }.to raise_error(Gush::WorkflowClassDoesNotExist)
      expect(called).to be(true)
    end

    it "does not error if a workflow's job class is no longer defined" do
      flow = TestWorkflow.create
      called = false
      allow_any_instance_of(Gush::Job).to receive(:as_json).and_wrap_original do |original, *args|
        called = true
        original.call(*args).merge({ klass: 'OldDeletedJob'})
      end
      flow.save
      expect {
        Gush::Workflow.page
      }.not_to raise_error
      expect {
        Gush::Client.new.find_workflow(flow.id)
      }.to raise_error(Gush::JobClassDoesNotExist)
      expect(called).to be(true)
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

  describe "#status" do
    context "when failed" do
      it "returns :failed" do
        flow = TestWorkflow.create
        flow.find_job("Prepare").fail!
        flow.persist!
        expect(flow.reload.status).to eq(:failed)
      end
    end

    it "returns failed" do
      subject.find_job('Prepare').fail!
      expect(subject.status).to eq(:failed)
    end

    it "returns running" do
      subject.find_job('Prepare').start!
      expect(subject.status).to eq(:running)
    end

    it "returns finished" do
      subject.jobs.each {|n| n.finish! }
      expect(subject.status).to eq(:finished)
    end

    it "returns stopped" do
      subject.stopped = true
      expect(subject.status).to eq(:stopped)
    end

    it "returns pending" do
      expect(subject.status).to eq(:pending)
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

      result = JSON.parse(klass.create("arg1", "arg2", arg3: 123).to_json)
      expected = {
          "id" => an_instance_of(String),
          "name" => klass.to_s,
          "klass" => klass.to_s,
          "job_klasses" => ["FetchFirstJob", "PersistFirstJob"],
          "status" => "pending",
          "total" => 2,
          "finished" => 0,
          "started_at" => nil,
          "finished_at" => nil,
          "stopped" => false,
          "dependencies" => [{
            "from" => "FetchFirstJob",
            "to" => job_with_id("PersistFirstJob")
          }],
          "arguments" => ["arg1", "arg2"],
          "kwargs" => {"arg3" => 123},
          "globals" => {}
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
      expect(flow.jobs.first.params).to eq({ something: 1 })
    end

    it "merges globals with params and passes them to the job, with job param taking precedence" do
      flow = Gush::Workflow.new(globals: { something: 2, global1: 123 })
      flow.run(Gush::Job, params: { something: 1 })
      flow.save
      expect(flow.jobs.first.params).to eq({ something: 1, global1: 123 })
    end

    it "allows passing wait param to the job" do
      flow = Gush::Workflow.new
      flow.run(Gush::Job, wait: 5.seconds)
      flow.save
      expect(flow.jobs.first.wait).to eq(5.seconds)
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
