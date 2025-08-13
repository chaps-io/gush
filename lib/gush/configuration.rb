module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis, :ttl, :locking_duration, :polling_interval

    def self.from_json(json)
      new(Gush::JSON.decode(json, symbolize_keys: true))
    end

    def initialize(hash = {})
      raise ArgumentError, "You can't set both redis_url and redis" if hash.key?(:redis_url) && hash.key?(:redis)

      self.concurrency      = hash.fetch(:concurrency, 5)
      self.namespace        = hash.fetch(:namespace, 'gush')
      self.redis            = hash.key?(:redis) ? hash.fetch(:redis) : { url: hash.fetch(:redis_url, 'redis://localhost:6379') }
      self.gushfile         = hash.fetch(:gushfile, 'Gushfile')
      self.ttl              = hash.fetch(:ttl, -1)
      self.locking_duration = hash.fetch(:locking_duration, 2) # how long you want to wait for the lock to be released, in seconds
      self.polling_interval = hash.fetch(:polling_internal, 0.3) # how long the polling interval should be, in seconds
    end

    def gushfile=(path)
      @gushfile = Pathname(path)
    end

    def gushfile
      @gushfile.realpath if @gushfile.exist?
    end

    def redis_url=(url)
      redis[:url] = url
    end

    def redis_url
      redis[:url]
    end

    def to_hash
      {
        concurrency:      concurrency,
        namespace:        namespace,
        redis_url:        redis_url,
        redis:            redis,
        ttl:              ttl,
        locking_duration: locking_duration,
        polling_interval: polling_interval
      }
    end

    def to_json
      Gush::JSON.encode(to_hash)
    end
  end
end
