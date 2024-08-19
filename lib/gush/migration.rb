module Gush
  class Migration
    def migrate
      return if migrated?

      up
      migrated!
    end

    def up
      # subclass responsibility
      raise NotImplementedError
    end

    def version
      self.class.version
    end

    def migrated?
      redis.sismember("gush.migration.schema_migrations", version)
    end

    private

    def migrated!
      redis.sadd("gush.migration.schema_migrations", version)
    end

    def client
      @client ||= Client.new
    end

    def redis
      Gush::Client.redis_connection(client.configuration)
    end
  end
end
