module Gush
  class Configuration
    attr_accessor :redis_url

    def initialize
      @redis_url = "redis://localhost:6379"
    end
  end
end
