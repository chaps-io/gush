require 'yajl'

module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis_url, :environment

    def self.from_json(json)
      new(Gush::JSON.decode(json, symbolize_keys: true))
    end

    def initialize(hash = {})
      self.concurrency = hash.fetch(:concurrency, 5)
      self.namespace   = hash.fetch(:namespace, 'gush')
      self.redis_url   = hash.fetch(:redis_url, 'redis://localhost:6379')
      self.gushfile    = hash.fetch(:gushfile, 'Gushfile.rb')
      self.environment = hash.fetch(:environment, 'development')
    end

    def gushfile=(path)
      @gushfile = Pathname(path)
    end

    def gushfile
      raise Thor::Error, "#{@gushfile} not found, please add it to your project".colorize(:red) unless @gushfile.exist?
      @gushfile.realpath
    end

    def to_hash
      {
        concurrency: concurrency,
        namespace:   namespace,
        redis_url:   redis_url,
        environment: environment,
        gushfile:    gushfile.to_path
      }
    end

    def to_json
      Gush::JSON.encode(to_hash)
    end
  end
end
