require 'spec_helper'

describe Gush::JSON do
  subject { described_class }

  describe ".encode" do
    it "encodes data to JSON" do
      expect(subject.encode({a: 123})).to eq("{\"a\":123}")
    end
  end

  describe ".decode" do
    it "decodes JSON to data" do
      expect(subject.decode("{\"a\":123}")).to eq({a: 123})
    end

    it "passes options to the internal parser" do
      expect(subject.decode("{\"a\":123}")).to eq({a: 123})
    end
  end
end
