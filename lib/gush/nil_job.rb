module Gush
  class NilJob < Job
    def name
      @name ||= "Removed - #{klass}|#{id}"
    end
  end
end
