require 'spec_helper'

describe Gush::LoggerBuilder do
  it 'takes a job as an argument' do
    builder = Gush::LoggerBuilder.new(:workflow, :job, :jid)
    expect(builder.job).to eq(:job)
  end

  it 'takes a workflow as an argument' do
    builder = Gush::LoggerBuilder.new(:workflow, :job, :jid)
    expect(builder.workflow).to eq(:workflow)
  end

  it 'takes a jid as an argument' do
    builder = Gush::LoggerBuilder.new(:workflow, :job, :jid)
    expect(builder.jid).to eq(:jid)
  end

  describe "#build" do
    it 'returns a logger for a job' do
      expect(Gush::LoggerBuilder.new(:workflow, :job, :jid).build).to be_a Gush::NullLogger
    end
  end
end

