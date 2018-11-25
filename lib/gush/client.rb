require 'connection_pool'

module Gush
  class Client
    attr_reader :configuration

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

      connection_pool.with do |redis|
        loop do
          job_id = SecureRandom.uuid
          available = !redis.hexists("gush.jobs.#{workflow_id}.#{job_klass}", job_id)

          break if available
        end
      end

      job_id
    end

    def next_free_workflow_id
      id = nil
      loop do
        id = SecureRandom.uuid
        available = connection_pool.with do |redis|
          !redis.exists("gush.workflow.#{id}")
        end

        break if available
      end

      id
    end

    def all_workflows
      connection_pool.with do |redis|
        redis.scan_each(match: "gush.workflows.*").map do |key|
          id = key.sub("gush.workflows.", "")
          find_workflow(id)
        end
      end
    end

    def find_workflow(id)
      connection_pool.with do |redis|
        data = redis.get("gush.workflows.#{id}")

        unless data.nil?
          hash = Gush::JSON.decode(data, symbolize_keys: true)
          keys = redis.scan_each(match: "gush.jobs.#{id}.*")

          nodes = keys.each_with_object([]) do |key, array|
            array.concat redis.hvals(key).map { |json| Gush::JSON.decode(json, symbolize_keys: true) }
          end

          workflow_from_hash(hash, nodes)
        else
          raise WorkflowNotFound.new("Workflow with given id doesn't exist")
        end
      end
    end

    def persist_workflow(workflow)
      connection_pool.with do |redis|
        redis.set("gush.workflows.#{workflow.id}", workflow.to_json)
        # Make sure graph exists in RedisGraph
        # TODO make it optional
        redis.call("GRAPH.QUERY", "gush.graphs.#{workflow.id}", "MERGE (:workflow {id: '#{workflow.id}'})")
      end

      workflow.jobs.each {|job| persist_job(workflow.id, job) }
      workflow.mark_as_persisted

      true
    end

    def persist_job(workflow_id, job)
      connection_pool.with do |redis|
        redis.hset("gush.jobs.#{workflow_id}.#{job.klass}", job.id, job.to_json)

        # Update job status in RedisGraph
        # TODO make it optional
        list, properties =  redis.call("GRAPH.QUERY", "gush.graphs.#{workflow_id}", "MATCH (j {id: '#{job.name}'}) SET j.status = '#{job.status}'")

        # Create job if not exists
        if !properties.include?("Properties set: 1")
          #puts "-- does not exist, creating job"
          redis.call("GRAPH.QUERY", "gush.graphs.#{workflow_id}", "CREATE (:job {id: '#{job.name}', status: '#{job.status}'})")
        end
      end
    end

    def create_relationships(workflow)
      connection_pool.with do |redis|
        workflow.jobs.each do |job|
          job.outgoing.each do |outgoing_name|
            create_relationship(redis, workflow, job.name, outgoing_name)
          end
        end
      end
    end

    def create_relationship(redis, workflow, incoming, outgoing)
      query = <<-CYPHER
        MATCH (in:job {id: '#{incoming}'}), (out:job {id: '#{outgoing}'})
        CREATE (in)-[:outgoing]->(out)
      CYPHER

      redis.call("GRAPH.QUERY", "gush.graphs.#{workflow.id}", query)
    end

    def job_has_dependencies_satisfied?(workflow_id, job_name)
      okay = successful_job_dependencies_count(workflow_id, job_name)
      total = total_job_dependencies_count(workflow_id, job_name)

      okay ==  total
    end

    def successful_job_dependencies_count(workflow_id, job_name)
      connection_pool.with do |redis|
        query = <<-CYPHER
          MATCH (in:job {status: 'succeeded'})-[:outgoing]->(out:job {id: '#{job_name}', status: 'pending'})
          RETURN count(in.id)
        CYPHER

        result = redis.call("GRAPH.QUERY", "gush.graphs.#{workflow_id}", query)

        return result[0][1][0].to_i rescue 0
      end
    end

    def total_job_dependencies_count(workflow_id, job_name)
      connection_pool.with do |redis|
        query = <<-CYPHER
          MATCH (in:job)-[:outgoing]->(out:job {id: '#{job_name}', status: 'pending'})
          RETURN count(in.id)
        CYPHER

        result = redis.call("GRAPH.QUERY", "gush.graphs.#{workflow_id}", query)

        return result[0][1][0].to_i rescue 0
      end
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
      connection_pool.with do |redis|
        redis.del("gush.workflows.#{workflow.id}")
      end
      workflow.jobs.each {|job| destroy_job(workflow.id, job) }
    end

    def destroy_job(workflow_id, job)
      connection_pool.with do |redis|
        redis.del("gush.jobs.#{workflow_id}.#{job.klass}")
      end
    end

    def expire_workflow(workflow, ttl=nil)
      ttl = ttl || configuration.ttl
      connection_pool.with do |redis|
        redis.expire("gush.workflows.#{workflow.id}", ttl)
      end
      workflow.jobs.each {|job| expire_job(workflow.id, job, ttl) }
    end

    def expire_job(workflow_id, job, ttl=nil)
      ttl = ttl || configuration.ttl
      connection_pool.with do |redis|
        redis.expire("gush.jobs.#{workflow_id}.#{job.name}", ttl)
      end
    end

    def enqueue_job(workflow_id, job)
      job.enqueue!
      persist_job(workflow_id, job)
      queue = job.queue || configuration.namespace

      Gush::Worker.set(queue: queue).perform_later(*[workflow_id, job.name])
    end

    private

    def find_job_by_klass_and_id(workflow_id, job_name)
      job_klass, job_id = job_name.split('|')

      connection_pool.with do |redis|
        redis.hget("gush.jobs.#{workflow_id}.#{job_klass}", job_id)
      end
    end

    def find_job_by_klass(workflow_id, job_name)
      new_cursor, result = connection_pool.with do |redis|
        redis.hscan("gush.jobs.#{workflow_id}.#{job_name}", 0, count: 1)
      end

      return nil if result.empty?

      job_id, job = *result[0]

      job
    end

    def workflow_from_hash(hash, nodes = [])
      flow = hash[:klass].constantize.new(*hash[:arguments])
      flow.jobs = []
      flow.stopped = hash.fetch(:stopped, false)
      flow.id = hash[:id]

      flow.jobs = nodes.map do |node|
        Gush::Job.from_hash(node)
      end

      flow
    end

    def build_redis
      Redis.new(url: configuration.redis_url).tap do |instance|
        RedisClassy.redis = instance
      end
    end

    def connection_pool
      @connection_pool ||= ConnectionPool.new(size: configuration.concurrency, timeout: 1) { build_redis }
    end
  end
end
