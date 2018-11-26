module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis_url, :ttl

    def self.from_json(json)
      new(Gush::JSON.decode(json))
    end

    def initialize(hash = {})
      self.concurrency = hash.fetch(:concurrency, 5)
      self.namespace   = hash.fetch(:namespace, 'gush')
      self.redis_url   = hash.fetch(:redis_url, 'redis://localhost:6379')
      self.gushfile    = hash.fetch(:gushfile, 'Gushfile')
      self.ttl         = hash.fetch(:ttl, -1)
    end

    def gushfile=(path)
      @gushfile = Pathname(path)
    end

    def gushfile
      @gushfile.realpath if @gushfile.exist?
    end

    def to_hash
      {
        concurrency: concurrency,
        namespace:   namespace,
        redis_url:   redis_url,
        ttl:         ttl
      }
    end

    def to_json
      Gush::JSON.encode(to_hash)
    end
  end
end
