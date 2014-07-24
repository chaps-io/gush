require 'spec_helper'

describe Gush::LoggerBuilder do
  it 'takes a job as an argument' do
    builder = Gush::LoggerBuilder.new(:job)
    expect(builder.job).to eq(:job)
  end

  describe "#build" do
    it 'returns a logger for a job' do
      expect(Gush::LoggerBuilder.new(:job).build).to be_a Gush::NullLogger
    end
  end
end

