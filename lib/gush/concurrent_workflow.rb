require 'gush/workflow'

module Gush
  class ConcurrentWorkflow < Workflow
    def run(job_class)
      super(job_class, true)
    end

    def synchronously(custom_name = nil, attach_concurrently = false, &block)
      super(custom_name, true, &block)
    end
  end
end
