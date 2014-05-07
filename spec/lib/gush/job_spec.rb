require 'spec_helper'

describe Gush::Job do
  describe "#as_json" do
    context "when finished and enqueued set to true" do
      it "returns correct hash" do
        job = described_class.new("a-job", finished: true, enqueued: true)
        expected = {
          name: "a-job",
          klass: "Gush::Job",
          finished: true,
          enqueued: true,
          failed: false,
          incoming: [],
          outgoing: []
        }
        expect(job.as_json).to eq(expected)
      end
    end
  end
end
