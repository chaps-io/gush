module Gush
  class LoggerBuilder
    attr_reader :workflow, :job, :jid

    def initialize(workflow, job, jid)
      @workflow = workflow
      @job = job
      @jid = jid
    end

    def build
      NullLogger.new
    end
  end
end
