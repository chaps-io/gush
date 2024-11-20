module Gush
  class WorkflowNotFound < StandardError; end
  class WorkflowClassDoesNotExist < StandardError; end
  class JobClassDoesNotExist < StandardError; end
  class DependencyLevelTooDeep < StandardError; end
end
