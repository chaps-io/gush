require 'spec_helper'

describe Gush::Job do

  describe "#fail!" do
    it "sets finished and failed to true and records time" do
      job = described_class.new(name: "a-job")
      job.fail!
      expect(job.failed_at).to eq(Time.now.to_i)
      expect(job.failed?).to eq(true)
      expect(job.finished?).to eq(true)
      expect(job.running?).to eq(false)
      expect(job.enqueued?).to eq(false)
    end
  end

  describe "#finish!" do
    it "sets finished to false and failed to false and records time" do
      job = described_class.new(name: "a-job")
      job.finish!
      expect(job.finished_at).to eq(Time.now.to_i)
      expect(job.failed?).to eq(false)
      expect(job.running?).to eq(false)
      expect(job.finished?).to eq(true)
      expect(job.enqueued?).to eq(false)
    end
  end

  describe "#enqueue!" do
    it "resets flags to false and sets enqueued to true" do
      job = described_class.new(name: "a-job")
      job.finished_at = 123
      job.failed_at = 123
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
      job = described_class.new(name: "a-job")
      job.start!
      expect(job.started_at).to eq(Time.now.to_i)
      expect(job.enqueued?).to eq(false)
      expect(job.running?).to eq(true)
    end
  end

  describe "#as_json" do
    context "finished and enqueued set to true" do
      it "returns correct hash" do
        job = described_class.new(double('flow'), name: "a-job", finished_at: 123, enqueued_at: 120)
        expected = {
          name: "a-job",
          klass: "Gush::Job",
          finished: true,
          enqueued: true,
          failed: false,
          incoming: [],
          outgoing: [],
          failed_at: nil,
          started_at: nil,
          finished_at: 123,
          enqueued_at: 120,
          running: false
        }
        expect(job.as_json).to eq(expected)
      end
    end
  end

  describe ".from_hash" do
    it "properly restores state of the job from hash" do
      job = described_class.from_hash(
        double('flow'),
        {
          klass: 'Gush::Job',
          name: 'gob',
          finished: true,
          failed: true,
          enqueued: true,
          incoming: ['a', 'b'],
          outgoing: ['c'],
          failed_at: 123,
          finished_at: 122,
          started_at: 55,
          enqueued_at: 444
        }
      )

      expect(job.name).to eq('gob')
      expect(job.class).to eq(Gush::Job)
      expect(job.finished?).to eq(true)
      expect(job.failed?).to eq(true)
      expect(job.enqueued?).to eq(true)
      expect(job.incoming).to eq(['a', 'b'])
      expect(job.outgoing).to eq(['c'])
      expect(job.failed_at).to eq(123)
      expect(job.finished_at).to eq(122)
      expect(job.started_at).to eq(55)
      expect(job.enqueued_at).to eq(444)
    end
  end
end
