module Gush
  class LoggerBuilder
    attr_reader :workflow, :job

    def initialize(workflow, job)
      @workflow = workflow
      @job = job
    end

    def build
      NullLogger.new
    end
  end
end
