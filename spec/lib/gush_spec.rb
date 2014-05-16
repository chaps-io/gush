require 'spec_helper'

describe Gush do
  describe ".gushfile" do
    context "Gushfile.rb is missing from pwd" do
      it "raises an exception" do
        path = Pathname.new("/tmp/Gushfile.rb")
        path.delete if path.exist?

        allow(Pathname).to receive(:pwd)
          .and_return(Pathname.new("/tmp"))
        expect {described_class.gushfile}.to raise_error(Thor::Error)
      end
    end

    context "Gushfile.rb exists" do
      it "returns Pathname to it" do
        path = Pathname.new("/tmp/Gushfile.rb")
        FileUtils.touch(path)
        allow(Pathname).to receive(:pwd)
          .and_return(Pathname.new("/tmp"))
        expect(described_class.gushfile).to eq(path)
        path.delete
      end
    end
  end

  describe ".root" do
    it "returns root directory of Gush" do
      expected = Pathname.new(__FILE__).parent.parent.parent
      expect(described_class.root).to eq(expected)
    end
  end

  describe ".configure" do
    it "runs block with config instance passed" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(Gush.configuration)
    end
  end

  describe ".workflow_from_hash" do
    it "constructs workflow object from JSON hash" do
      flow = TestWorkflow.new("workflow")
      hash = Yajl::Parser.parse(flow.to_json, symbolize_keys: true)

      flow_parsed = Gush.workflow_from_hash(hash)

      hash_parsed = Yajl::Parser.parse(flow_parsed.to_json, symbolize_keys: true)

      expect(hash_parsed[:name]).to eq(hash[:name])
      expect(hash_parsed[:klass]).to eq(hash[:klass])
      expect(hash_parsed[:nodes]).to match_array(hash[:nodes])

      path = flow_parsed.find_job('NormalizeJob').dependencies(flow).map(&:name)
      path_expected = flow.find_job('NormalizeJob').dependencies(flow).map(&:name)

      expect(path).to match_array(path_expected)
    end
  end

  describe ".start_workflow" do
    it "enqueues next jobs from the workflow" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      Gush.persist_workflow(workflow, @redis)
      expect {
        Gush.start_workflow(id, {redis: @redis})
      }.to change{Prepare.jobs.count}.from(0).to(1)
    end

    it "marks the enqueued jobs as running" do
      id = SecureRandom.uuid
      workflow = TestWorkflow.new(id)
      Gush.persist_workflow(workflow, @redis)
      Gush.start_workflow(id, {redis: @redis})
      job = Gush.find_workflow(id, @redis).find_job("Prepare")
      expect(job.running?).to eq(true)
    end
  end

  describe ".persist_job" do
    it "persists JSON dump of the job in Redis" do
      redis = double("redis")
      job = double("job", to_json: 'json')
      expect(redis).to receive(:set).with("gush.jobs.deadbeef.#{job.class.to_s}", 'json')
      Gush.persist_job('deadbeef', job, redis)
    end
  end
end
