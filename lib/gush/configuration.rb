require 'yajl'

module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis_url
    attr_writer :gushfile

    def self.from_json(json)
      new(Yajl::Parser.parse(json, symbolize_keys: true))
    end

    def initialize(hash = {})
      @concurrency = hash.fetch(:concurrency, 5)
      @namespace   = hash.fetch(:namespace, 'gush')
      @redis_url   = hash.fetch(:redis_url, 'redis://localhost:6379')
      @gushfile    = hash.fetch(:gushfile, 'Gushfile.rb')
    end

    def gushfile
      path = Pathname.pwd.join(@gushfile)
      raise Thor::Error, "#{path.basename} not found, please add it to your project".colorize(:red) unless path.exist?
      path
    end

    def to_hash
      {
        concurrency: concurrency,
        namespace:   namespace,
        redis_url:   redis_url,
        gushfile:    gushfile
      }
    end

    def to_json
      Yajl::Encoder.new.encode(to_hash)
    end
  end
end
