require 'gush/workflow'

module Gush
  class ConcurrentWorkflow < Workflow
    def run(job_class)
      super(job_class, true)
    end
  end
end
