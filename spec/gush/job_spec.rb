require 'spec_helper'

describe Gush::Job do

  describe "#output" do
    it "saves output to output_payload" do
      job = described_class.new
      job.output "something"
      expect(job.output_payload).to eq("something")
    end
  end
  describe "#fail!" do
    it "sets finished and failed to true and records time" do
      job = described_class.new
      job.fail!
      expect(job.failed_at).to be_within(1.second).of(Time.now)
      expect(job.failed?).to eq(true)
      expect(job.finished?).to eq(true)
      expect(job.running?).to eq(false)
      expect(job.enqueued?).to eq(false)
    end
  end

  describe "#finish!" do
    it "sets finished to false and failed to false and records time" do
      job = described_class.new
      job.finish!
      expect(job.finished_at).to be_within(1.second).of(Time.now)
      expect(job.failed?).to eq(false)
      expect(job.running?).to eq(false)
      expect(job.finished?).to eq(true)
      expect(job.enqueued?).to eq(false)
    end
  end

  describe "#enqueue!" do
    it "resets flags to false and sets enqueued to true" do
      job = described_class.new
      job.finished_at = Time.current
      job.failed_at = Time.current
      job.enqueue!
      expect(job.started_at).to eq(nil)
      expect(job.finished_at).to eq(nil)
      expect(job.failed_at).to eq(nil)
      expect(job.failed?).to eq(false)
      expect(job.finished?).to eq(false)
      expect(job.enqueued?).to eq(true)
      expect(job.running?).to eq(false)
    end
  end

  describe "#start!" do
    it "resets flags and marks as running" do
      job = described_class.new

      job.enqueue!
      job.fail!

      expect(job.started_at).to eq(nil)
      expect(job.failed_at).to be_within(1.second).of(Time.now)

      job.start!

      expect(job.started_at).to be_within(1.second).of(Time.now)
      expect(job.failed_at).to eq(nil)
    end
  end
end
