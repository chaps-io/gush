require 'spec_helper'

describe Gush::Configuration do

  it "has defaults set" do
    expect(Gush.configuration.redis_url).to eq("redis://localhost:6379")
    expect(Gush.configuration.concurrency).to eq(5)
  end

  describe "#configure" do
    it "allows setting options through a block" do
      Gush.configure do |config|
        config.redis_url = "asd"
        config.concurrency = 25
      end

      expect(Gush.configuration.redis_url).to eq("asd")
      expect(Gush.configuration.concurrency).to eq(25)
    end
  end
end
