ActiveJob::Base.queue_adapter = :inline
ActiveJob::Base.logger = Logger.new(nil)

class SmallJob < Gush::Job

end

class FinalJob < Gush::Job

end


class BigWorkflow < Gush::Workflow
  def configure
    jobs = []

    1000.times do
      jobs << run(SmallJob)
    end

    run FinalJob, after: jobs
  end
end