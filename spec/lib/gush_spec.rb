require 'spec_helper'

describe Gush do
  describe "#workflow_from_hash" do
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
end
