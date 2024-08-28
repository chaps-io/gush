require 'redis'
require 'concurrent-ruby'

module Gush
  class Client
    attr_reader :configuration

    @@redis_connection = Concurrent::ThreadLocalVar.new(nil)

    def self.redis_connection(config)
      cached = (@@redis_connection.value ||= { url: config.redis_url, connection: nil })
      return cached[:connection] if !cached[:connection].nil? && config.redis_url == cached[:url]

      Redis.new(url: config.redis_url).tap do |instance|
        RedisClassy.redis = instance
        @@redis_connection.value = { url: config.redis_url, connection: instance }
      end
    end

    def initialize(config = Gush.configuration)
      @configuration = config
    end

    def configure
      yield configuration
    end

    def create_workflow(name)
      begin
        name.constantize.create
      rescue NameError
        raise WorkflowNotFound.new("Workflow with given name doesn't exist")
      end
      flow
    end

    def start_workflow(workflow, job_names = [])
      workflow.mark_as_started
      persist_workflow(workflow)

      jobs = if job_names.empty?
               workflow.initial_jobs
             else
               job_names.map {|name| workflow.find_job(name) }
             end

      jobs.each do |job|
        enqueue_job(workflow.id, job)
      end
    end

    def stop_workflow(id)
      workflow = find_workflow(id)
      workflow.mark_as_stopped
      persist_workflow(workflow)
    end

    def next_free_job_id(workflow_id, job_klass)
      job_id = nil

      loop do
        job_id = SecureRandom.uuid
        available = !redis.hexists("gush.jobs.#{workflow_id}.#{job_klass}", job_id)

        break if available
      end

      job_id
    end

    def next_free_workflow_id
      id = nil
      loop do
        id = SecureRandom.uuid
        available = !redis.exists?("gush.workflows.#{id}")

        break if available
      end

      id
    end

    # Returns the specified range of workflow ids, sorted by created timestamp.
    #
    # @param start, stop [Integer] see https://redis.io/docs/latest/commands/zrange/#index-ranges
    #   for details on the start and stop parameters.
    # @param by_ts [Boolean] if true, start and stop are treated as timestamps
    #   rather than as element indexes, which allows the workflows to be indexed
    #   by created timestamp
    # @param order [Symbol] if :asc, finds ids in ascending created timestamp;
    #   if :desc, finds ids in descending created timestamp
    # @returns [Array<String>] array of workflow ids
    def workflow_ids(start=nil, stop=nil, by_ts: false, order: :asc)
      start ||= 0
      stop ||= 99

      redis.zrange(
        "gush.idx.workflows.created_at",
        start,
        stop,
        by_score: by_ts,
        rev: order&.to_sym == :desc
      )
    end

    def workflows(start=nil, stop=nil, **kwargs)
      workflow_ids(start, stop, **kwargs).map { |id| find_workflow(id) }
    end

    def workflows_count
      redis.zcard('gush.idx.workflows.created_at')
    end

    # Deprecated.
    #
    # This method is not performant when there are a large number of workflows
    # or when the redis keyspace is large. Use workflows instead with pagination.
    def all_workflows
      redis.scan_each(match: "gush.workflows.*").map do |key|
        id = key.sub("gush.workflows.", "")
        find_workflow(id)
      end
    end

    def find_workflow(id)
      data = redis.get("gush.workflows.#{id}")

      unless data.nil?
        hash = Gush::JSON.decode(data, symbolize_keys: true)

        if hash[:job_klasses]
          keys = hash[:job_klasses].map { |klass| "gush.jobs.#{id}.#{klass}" }
        else
          # For backwards compatibility, get job keys via a full keyspace scan
          keys = redis.scan_each(match: "gush.jobs.#{id}.*")
        end

        nodes = keys.each_with_object([]) do |key, array|
          array.concat(redis.hvals(key).map { |json| Gush::JSON.decode(json, symbolize_keys: true) })
        end

        workflow_from_hash(hash, nodes)
      else
        raise WorkflowNotFound.new("Workflow with given id doesn't exist")
      end
    end

    def persist_workflow(workflow)
      created_at = Time.now.to_f
      added = redis.zadd("gush.idx.workflows.created_at", created_at, workflow.id, nx: true)

      if added && configuration.ttl&.positive?
        expires_at = created_at + configuration.ttl
        redis.zadd("gush.idx.workflows.expires_at", expires_at, workflow.id, nx: true)
      end

      redis.set("gush.workflows.#{workflow.id}", workflow.to_json)

      workflow.jobs.each {|job| persist_job(workflow.id, job, expires_at: expires_at) }
      workflow.mark_as_persisted

      true
    end

    def persist_job(workflow_id, job, expires_at: nil)
      redis.zadd("gush.idx.jobs.expires_at", expires_at, "#{workflow_id}.#{job.klass}", nx: true) if expires_at

      redis.hset("gush.jobs.#{workflow_id}.#{job.klass}", job.id, job.to_json)
    end

    def find_job(workflow_id, job_name)
      job_name_match = /(?<klass>\w*[^-])-(?<identifier>.*)/.match(job_name)

      data = if job_name_match
               find_job_by_klass_and_id(workflow_id, job_name)
             else
               find_job_by_klass(workflow_id, job_name)
             end

      return nil if data.nil?

      data = Gush::JSON.decode(data, symbolize_keys: true)
      Gush::Job.from_hash(data)
    end

    def destroy_workflow(workflow)
      redis.del("gush.workflows.#{workflow.id}")
      redis.zrem("gush.idx.workflows.created_at", workflow.id)
      redis.zrem("gush.idx.workflows.expires_at", workflow.id)
      workflow.jobs.each {|job| destroy_job(workflow.id, job) }
    end

    def destroy_job(workflow_id, job)
      redis.del("gush.jobs.#{workflow_id}.#{job.klass}")
      redis.zrem("gush.idx.jobs.expires_at", "#{workflow_id}.#{job.klass}")
    end

    def expire_workflows(expires_at=nil)
      expires_at ||= Time.now.to_f

      ids = redis.zrange("gush.idx.workflows.expires_at", "-inf", expires_at, by_score: true)
      return if ids.empty?

      redis.del(ids.map { |id| "gush.workflows.#{id}" })
      redis.zrem("gush.idx.workflows.created_at", ids)
      redis.zrem("gush.idx.workflows.expires_at", ids)

      expire_jobs(expires_at)
    end

    def expire_jobs(expires_at=nil)
      expires_at ||= Time.now.to_f

      keys = redis.zrange("gush.idx.jobs.expires_at", "-inf", expires_at, by_score: true)
      return if keys.empty?

      redis.del(keys.map { |key| "gush.jobs.#{key}" })
      redis.zrem("gush.idx.jobs.expires_at", keys)
    end

    def expire_workflow(workflow, ttl=nil)
      ttl ||= configuration.ttl

      if ttl&.positive?
        redis.zadd("gush.idx.workflows.expires_at", Time.now.to_f + ttl, workflow.id)
      else
        redis.zrem("gush.idx.workflows.expires_at", workflow.id)
      end

      workflow.jobs.each {|job| expire_job(workflow.id, job, ttl) }
    end

    def expire_job(workflow_id, job, ttl=nil)
      ttl ||= configuration.ttl

      if ttl&.positive?
        redis.zadd("gush.idx.jobs.expires_at", Time.now.to_f + ttl, "#{workflow_id}.#{job.klass}")
      else
        redis.zrem("gush.idx.jobs.expires_at", "#{workflow_id}.#{job.klass}")
      end
    end

    def enqueue_job(workflow_id, job)
      job.enqueue!
      persist_job(workflow_id, job)

      options = { queue: configuration.namespace }.merge(job.worker_options)
      job.enqueue_worker!(options)
    end

    private

    def find_job_by_klass_and_id(workflow_id, job_name)
      job_klass, job_id = job_name.split('|')

      redis.hget("gush.jobs.#{workflow_id}.#{job_klass}", job_id)
    end

    def find_job_by_klass(workflow_id, job_name)
      new_cursor, result = redis.hscan("gush.jobs.#{workflow_id}.#{job_name}", 0, count: 1)
      return nil if result.empty?

      job_id, job = *result[0]

      job
    end

    def workflow_from_hash(hash, nodes = [])
      jobs = nodes.map do |node|
        Gush::Job.from_hash(node)
      end

      internal_state = {
        persisted: true,
        jobs: jobs,
        # For backwards compatibility, setup can only be skipped for a persisted
        # workflow if there is no data missing from the persistence.
        # 2024-07-23: dependencies added to persistence
        skip_setup: !hash[:dependencies].nil?
      }.merge(hash)

      hash[:klass].constantize.new(
        *hash[:arguments],
        **hash[:kwargs],
        globals: hash[:globals],
        internal_state: internal_state
      )
    end

    def redis
      self.class.redis_connection(configuration)
    end
  end
end
