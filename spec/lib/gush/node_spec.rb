require 'spec_helper'

describe Gush::Node do

  describe "#dependencies" do
    it "returns all dependent nodes" do
      a = described_class.new("first")
      b = described_class.new("second")
      bb = described_class.new("second-parallel")
      c = described_class.new("third")

      b.connect_from(a)
      c.connect_from(b)
      c.connect_from(bb)

      expect(c.dependencies.map(&:name)).to match_array(["first", "second", "second-parallel"])
    end
  end
end
