require 'spec_helper'

describe Gush::Configuration do

  it "has defaults set" do
    expect(subject.redis_url).to eq("redis://localhost:6379")
    expect(subject.concurrency).to eq(5)
    expect(subject.namespace).to eq('gush')
    expect(subject.gushfile).to eq(Pathname.pwd.join('Gushfile.rb'))
  end

  describe "#configure" do
    it "allows setting options through a block" do
      Gush.configure do |config|
        config.redis_url = "redis://localhost"
        config.concurrency = 25
      end

      expect(Gush.configuration.redis_url).to eq("redis://localhost")
      expect(Gush.configuration.concurrency).to eq(25)
    end
  end
end
