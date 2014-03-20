module Gush
  class Configuration
    attr_accessor :redis_url, :concurrency

    def initialize
      @redis_url = "redis://localhost:6379"
      @concurrency = 5
    end
  end
end
