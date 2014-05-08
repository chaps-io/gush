module Gush
  class Configuration
    attr_accessor :redis_url, :concurrency, :mutex

    def initialize
      @redis_url = "redis://localhost:6379"
      @mutex = { block: 25, sleep: 0.5, expire: 35 }
      @concurrency = 5
    end
  end
end
