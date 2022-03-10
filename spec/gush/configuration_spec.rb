require 'spec_helper'

describe Gush::Configuration do

  it "has defaults set" do
    subject.gushfile = GUSHFILE
    expect(subject.redis_url).to eq("redis://localhost:6379")
    expect(subject.concurrency).to eq(5)
    expect(subject.namespace).to eq('gush')
    expect(subject.gushfile).to eq(GUSHFILE.realpath)
    expect(subject.locking_duration).to eq(2)
    expect(subject.polling_interval).to eq(0.3)
  end

  describe "#configure" do
    it "allows setting options through a block" do
      Gush.configure do |config|
        config.redis_url = "redis://localhost"
        config.concurrency = 25
        config.locking_duration = 5
        config.polling_interval = 0.5
      end

      expect(Gush.configuration.redis_url).to eq("redis://localhost")
      expect(Gush.configuration.concurrency).to eq(25)
      expect(Gush.configuration.locking_duration).to eq(5)
      expect(Gush.configuration.polling_interval).to eq(0.5)
    end
  end
end
