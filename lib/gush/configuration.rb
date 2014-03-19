module Gush
  class Configuration
    attr_accessor :redis_url, :workflows_path

    def initialize
      @redis_url = "redis://localhost:6379"
    end
  end
end
