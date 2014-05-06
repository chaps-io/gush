module Gush
  class Configuration
    attr_accessor :redis_url, :concurrency, :mutex

    def initialize
      @redis_url = "redis://localhost:6379"
      @mutex = { block: 5, sleep: 0.3, expire: 15 }
      @concurrency = 5
    end
  end
end
