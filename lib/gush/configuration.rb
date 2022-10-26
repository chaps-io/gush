module Gush
  class Configuration
    attr_accessor :concurrency, :namespace, :redis_url, :ttl, :locking_duration, :polling_interval, :pool_size, :pool_timeout

    def self.from_json(json)
      new(Gush::JSON.decode(json))
    end

    def initialize(hash = {})
      self.concurrency      = hash.fetch(:concurrency, 5)
      self.pool_size        = hash.fetch(:concurrency, 5)
      self.pool_timeout     = hash.fetch(:concurrency, 2)
      self.namespace        = hash.fetch(:namespace, 'gush')
      self.redis_url        = hash.fetch(:redis_url, 'redis://localhost:6379')
      self.gushfile         = hash.fetch(:gushfile, 'Gushfile')
      self.ttl              = hash.fetch(:ttl, -1)
      self.locking_duration = hash.fetch(:locking_duration, 2000) # how long you want to wait for the lock to be released, in miliseconds
      self.polling_interval = hash.fetch(:polling_internal, 300) # how long the polling interval should be, in miliseconds
    end

    def gushfile=(path)
      @gushfile = Pathname(path)
    end

    def gushfile
      @gushfile.realpath if @gushfile.exist?
    end

    def to_hash
      {
        concurrency:      concurrency,
        namespace:        namespace,
        redis_url:        redis_url,
        ttl:              ttl,
        locking_duration: locking_duration,
        polling_interval: polling_interval,
        pool_size:        pool_size,
        pool_timeout:     pool_timeout
      }
    end

    def to_json
      Gush::JSON.encode(to_hash)
    end
  end
end
