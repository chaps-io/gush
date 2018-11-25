ActiveJob::Base.queue_adapter = :inline
ActiveJob::Base.logger = Logger.new(nil)
$small_jobs = 0
$final_jobs = 0
$medium_jobs = 0

class SmallJob < Gush::Job
  def perform
    $small_jobs += 1
  end
end

class MediumJob < Gush::Job
  def perform
    $medium_jobs += 1
  end
end

class FinalJob < Gush::Job
  def perform
    payloads
    $final_jobs += 1
  end
end


class BigWorkflow < Gush::Workflow
  def configure
    jobs = 500.times.map do
      a = run(SmallJob)
      run(MediumJob, after: a)
    end

    run FinalJob, after: jobs
  end
end