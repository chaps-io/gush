module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis_url

    def initialize
      @concurrency = 5
      @namespace = "gush"
      @redis_url = "redis://localhost:6379"
    end
  end
end
