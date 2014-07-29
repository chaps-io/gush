require 'spec_helper'

describe Gush::LoggerBuilder do
  it 'takes a job as an argument' do
    builder = Gush::LoggerBuilder.new(:workflow, :job)
    expect(builder.job).to eq(:job)
  end

  it 'takes a workflow as an argument' do
    builder = Gush::LoggerBuilder.new(:workflow, :job)
    expect(builder.workflow).to eq(:workflow)
  end

  describe "#build" do
    it 'returns a logger for a job' do
      expect(Gush::LoggerBuilder.new(:workflow, :job).build).to be_a Gush::NullLogger
    end
  end
end

