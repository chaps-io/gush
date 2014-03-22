require 'spec_helper'

describe Gush::Node do

  describe "#dependencies" do
    it "returns all dependent nodes" do
      a = described_class.new("first")
      b = described_class.new("second")
      bb = described_class.new("second-parallel")
      c = described_class.new("third")

      a.connect_to(b)
      b.connect_to(c)
      bb.connect_to(c)

      expect(c.dependencies.map(&:name)).to match_array(["first", "second", "second-parallel"])
    end
  end
end
