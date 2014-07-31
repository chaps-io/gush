module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis_url

    def initialize
      @concurrency = 5
      @namespace = "gush"
      @redis_url = "redis://localhost:6379"
    end

    def to_hash
      {
        concurrency: concurrency,
        namespace:   namespace,
        redis_url:   redis_url
      }
    end

    def to_json
      Yajl::Encoder.new.encode(to_hash)
    end
  end
end
