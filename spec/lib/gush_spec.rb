require 'spec_helper'

describe Gush do
  describe "#workflow_from_hash" do
    it "constructs workflow object from JSON hash" do
      flow = TestWorkflow.new("workflow")
      hash = JSON.parse(flow.to_json)

      flow_parsed = Gush.workflow_from_hash(hash)

      hash_parsed = JSON.parse(flow_parsed.to_json)

      expect(hash_parsed["name"]).to eq(hash["name"])
      expect(hash_parsed["klass"]).to eq(hash["klass"])
      expect(hash_parsed["nodes"]).to match_array(hash["nodes"])
      expect(hash_parsed["edges"]).to match_array(hash["edges"])

      path = flow_parsed.find_job('NormalizeJob').dependencies.map(&:name)
      path_expected = flow.find_job('NormalizeJob').dependencies.map(&:name)

      expect(path).to match_array(path_expected)
    end
  end
end
