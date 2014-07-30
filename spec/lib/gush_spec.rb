require 'spec_helper'

describe Gush do
  describe ".gushfile" do
    context "Gushfile.rb is missing from pwd" do
      it "raises an exception" do
        path = Pathname.new("/tmp/Gushfile.rb")
        path.delete if path.exist?

        allow(Pathname).to receive(:pwd)
          .and_return(Pathname.new("/tmp"))
        expect {Gush.gushfile}.to raise_error(Thor::Error)
      end
    end

    context "Gushfile.rb exists" do
      it "returns Pathname to it" do
        path = Pathname.new("/tmp/Gushfile.rb")
        FileUtils.touch(path)
        allow(Pathname).to receive(:pwd)
          .and_return(Pathname.new("/tmp"))
        expect(Gush.gushfile).to eq(path)
        path.delete
      end
    end
  end

  describe ".root" do
    it "returns root directory of Gush" do
      expected = Pathname.new(__FILE__).parent.parent.parent
      expect(Gush.root).to eq(expected)
    end
  end

  describe ".configure" do
    it "runs block with config instance passed" do
      expect { |b| Gush.configure(&b) }.to yield_with_args(Gush.configuration)
    end
  end

  describe ".find_workflow" do
    context "when workflow doesn't exist" do
      it "returns nil" do
        expect {
          Gush.find_workflow('nope')
        }.to raise_error(WorkflowNotFoundError)
      end
    end

    context "when given workflow exists" do
      it "returns Workflow object" do
        expected_workflow = TestWorkflow.new(SecureRandom.uuid)
        Gush.persist_workflow(expected_workflow)
        workflow = Gush.find_workflow(expected_workflow.id)

        expect(workflow.id).to eq(expected_workflow.id)
        expect(workflow.nodes.map(&:name)).to match_array(expected_workflow.nodes.map(&:name))
      end
    end
  end

  describe ".workflow_from_hash" do
    it "constructs workflow object from JSON hash" do
      flow = TestWorkflow.new("workflow")
      hash = Yajl::Parser.parse(flow.to_json, symbolize_keys: true)

      flow_parsed = Gush.workflow_from_hash(hash)

      hash_parsed = Yajl::Parser.parse(flow_parsed.to_json, symbolize_keys: true)

      expect(hash_parsed[:id]).to eq(hash[:id])
      expect(hash_parsed[:klass]).to eq(hash[:klass])
      expect(hash_parsed[:nodes]).to match_array(hash[:nodes])
      expect(hash_parsed[:logger_builder]).to eq("TestLoggerBuilder")

      path = flow_parsed.find_job('NormalizeJob').dependencies(flow).map(&:name)
      path_expected = flow.find_job('NormalizeJob').dependencies(flow).map(&:name)

      expect(path).to match_array(path_expected)
    end
  end

  describe ".start_workflow" do
    it "enqueues next jobs from the workflow" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      Gush.persist_workflow(workflow)
      expect {
        Gush.start_workflow(id)
      }.to change{Prepare.jobs.count}.from(0).to(1)
    end

    it "removes stopped flag when the workflow is started" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      workflow.stop!
      Gush.persist_workflow(workflow)
      expect {
        Gush.start_workflow(id)
      }.to change{Gush.find_workflow(id).stopped?}.from(true).to(false)
    end

    it "marks the enqueued jobs as running" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      Gush.persist_workflow(workflow)
      Gush.start_workflow(id)
      job = Gush.find_workflow(id).find_job("Prepare")
      expect(job.running?).to eq(true)
    end
  end

  describe ".stop_workflow" do
    it "marks the workflow as stopped" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      Gush.persist_workflow(workflow)
      expect {
        Gush.stop_workflow(id)
      }.to change{Gush.find_workflow(id).stopped?}.from(false).to(true)
    end
  end

  describe ".persist_workflow" do
    it "persists JSON dump of the Workflow and its jobs" do
      job = double("job", to_json: 'json')
      workflow = double("workflow", id: 'abcd', nodes: [job, job, job], to_json: '"json"')
      expect(Gush).to receive(:persist_job).exactly(3).times.with(workflow.id, job)
      Gush.persist_workflow(workflow)
      expect(Gush.redis.keys("gush.workflows.abcd").length).to eq(1)
    end
  end

  describe ".destroy_workflow" do
    it "removes all Redis keys related to the workflow" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      Gush.persist_workflow(workflow)
      expect(@redis.keys("gush.workflows.#{id}").length).to eq(1)
      expect(@redis.keys("gush.jobs.#{id}.*").length).to eq(5)

      Gush.destroy_workflow(workflow)

      expect(@redis.keys("gush.workflows.#{id}").length).to eq(0)
      expect(@redis.keys("gush.jobs.#{id}.*").length).to eq(0)
    end
  end

  describe ".persist_job" do
    it "persists JSON dump of the job in Redis" do
      job = double("job", to_json: 'json')
      Gush.persist_job('deadbeef', job)
      expect(Gush.redis.keys("gush.jobs.deadbeef.*").length).to eq(1)
    end
  end

  describe ".all_workflows" do
    it "returns all registered workflows" do
      workflow = TestWorkflow.new(SecureRandom.uuid)
      Gush.persist_workflow(workflow)
      workflows = Gush.all_workflows()
      expect(workflows.map(&:id)).to eq([workflow.id])
    end
  end
end
