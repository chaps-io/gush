require 'spec_helper'

describe Gush::Configuration do

  it "has default Redis URL configured" do
    expect(Gush.configuration.redis_url).to eq("redis://localhost:6379")
  end

  describe "#configure" do
    it "allows setting options through a block" do
      Gush.configure do |config|
        config.redis_url = "asd"
      end

      expect(Gush.configuration.redis_url).to eq("asd")
    end
  end
end
