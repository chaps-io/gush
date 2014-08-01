require 'yajl'

module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis_url

    def self.from_json(json)
      new(Yajl::Parser.parse(json, symbolize_keys: true))
    end

    def initialize(hash = {})
      @concurrency = hash.fetch(:concurrency, 5)
      @namespace   = hash.fetch(:namespace, 'gush')
      @redis_url   = hash.fetch(:redis_url, 'redis://localhost:6379')
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
