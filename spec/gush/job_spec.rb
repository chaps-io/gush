require 'spec_helper'

describe Gush::Job do

  describe "#output" do
    it "saves output to output_payload" do
      job = described_class.new(name: "a-job")
      job.output "something"
      expect(job.output_payload).to eq("something")
    end
  end
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

  describe "#enqueue_worker!" do
    it "enqueues the job using Gush::Worker" do
      job = described_class.new(name: "a-job", workflow_id: 123)

      expect {
        job.enqueue_worker!
      }.to change{ActiveJob::Base.queue_adapter.enqueued_jobs.size}.from(0).to(1)
    end

    it "handles ActiveJob.set options" do
      freeze_time = Time.utc(2023, 01, 21, 14, 36, 0)

      travel_to freeze_time do
        job = described_class.new(name: "a-job", workflow_id: 123)
        job.enqueue_worker!(wait_until: freeze_time + 5.minutes)
        expect(Gush::Worker).to have_a_job_enqueued_at(123, job_with_id(job.class.name), 5.minutes)
      end
    end
  end

  describe "#worker_options" do
    it "returns a blank options hash by default" do
      job = described_class.new
      expect(job.worker_options).to eq({})
    end

    it "returns a hash with the queue setting" do
      job = described_class.new
      job.queue = 'my-queue'
      expect(job.worker_options).to eq({ queue: 'my-queue' })
    end

    it "returns a hash with the wait setting" do
      job = described_class.new
      job.wait = 123
      expect(job.worker_options).to eq({ wait: 123 })
    end
  end

  describe "#start!" do
    it "resets flags and marks as running" do
      job = described_class.new(name: "a-job")

      job.enqueue!
      job.fail!

      now = Time.now.to_i
      expect(job.started_at).to eq(nil)
      expect(job.failed_at).to eq(now)

      job.start!

      expect(job.started_at).to eq(Time.now.to_i)
      expect(job.failed_at).to eq(nil)
    end
  end

  describe "#as_json" do
    context "finished and enqueued set to true" do
      it "returns correct hash" do
        job = described_class.new(
          workflow_id: 123,
          id: '702bced5-bb72-4bba-8f6f-15a3afa358bd',
          finished_at: 123,
          enqueued_at: 120,
          wait: 300
        )
        expected = {
          id: '702bced5-bb72-4bba-8f6f-15a3afa358bd',
          klass: "Gush::Job",
          incoming: [],
          outgoing: [],
          failed_at: nil,
          started_at: nil,
          finished_at: 123,
          enqueued_at: 120,
          params: {},
          queue: nil,
          output_payload: nil,
          workflow_id: 123,
          wait: 300
        }
        expect(job.as_json).to eq(expected)
      end
    end
  end

  describe ".from_hash" do
    it "properly restores state of the job from hash" do
      job = described_class.from_hash(
        {
          klass: 'Gush::Job',
          id: '702bced5-bb72-4bba-8f6f-15a3afa358bd',
          incoming: ['a', 'b'],
          outgoing: ['c'],
          failed_at: 123,
          finished_at: 122,
          started_at: 55,
          enqueued_at: 444
        }
      )

      expect(job.id).to eq('702bced5-bb72-4bba-8f6f-15a3afa358bd')
      expect(job.name).to eq('Gush::Job|702bced5-bb72-4bba-8f6f-15a3afa358bd')
      expect(job.class).to eq(Gush::Job)
      expect(job.klass).to eq("Gush::Job")
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
