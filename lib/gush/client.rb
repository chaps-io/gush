require 'redis'
require 'concurrent-ruby'

module Gush
  class Client
    attr_reader :configuration

    def self.connection_pool(config)
      @@redis_pool ||= ConnectionPool.new(size: config.pool_size, timeout: config.pool_timeout) do
        Redis.new(url: config.redis_url)
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

    def initial_job_ids(workflow_id)
      redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (j:Job) WHERE NOT ()-[:OUTGOING]->(j) RETURN j.id"
        )
      end[1].flatten
    end

    def all_workflows
      redis.with do |conn|
        conn.scan_each(match: "gush.workflows.*").map do |key|
          id = key.sub("gush.workflows.", "")
          find_workflow(id)
        end
      end
    end

    def find_workflow(id)
      data = redis.with { |conn| conn.get("gush.workflows.#{id}") }

      unless data.nil?
        hash = Gush::JSON.decode(data)
        keys = redis.with { |conn| conn.scan_each(match: "gush.jobs.#{id}.*") }

        nodes = keys.each_with_object([]) do |key, array|
          array.concat redis.with { |conn| conn.hvals(key).map { |json| Gush::JSON.decode(json) } }
        end

        workflow_from_hash(hash, nodes)
      else
        raise WorkflowNotFound.new("Workflow with given id doesn't exist")
      end
    end

    def persist_workflow(workflow)
      persist_jobs(workflow)
      persist_job_dependencies(workflow)

      true
    end

    def persist_jobs(workflow)
      redis.with do |conn|
        conn.multi do |multi|
          workflow.jobs.each do |job|
            multi.call(
              "GRAPH.QUERY",
              "workflow-#{workflow.id}",
              "CREATE (n:Job {id: '#{job.id}', name: '#{job.klass}'})"
            )
          end
        end
      end
    end

    def persist_job_dependencies(workflow)
      redis.with do |conn|
        conn.multi do |multi|
          workflow.connections.each do |incoming, outgoing|
            multi.call(
              "GRAPH.QUERY",
              "workflow-#{workflow.id}",
              %{
                MATCH (j:Job {id: '#{incoming}'}), (o:Job {id: '#{outgoing}'})
                CREATE (j)-[:OUTGOING]->(o)
              }
            )
          end
        end
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

      data = Gush::JSON.decode(data)
      Gush::Job.from_hash(data)
    end

    def destroy_workflow(workflow)
      redis.with { |conn| conn.del("gush.workflows.#{workflow.id}") }
      workflow.jobs.each {|job| destroy_job(workflow.id, job) }
    end

    def destroy_job(workflow_id, job)
      redis.with { |conn| conn.del("gush.jobs.#{workflow_id}.#{job.klass}") }
    end

    def expire_workflow(workflow, ttl=nil)
      ttl = ttl || configuration.ttl
      redis.with { |conn| conn.expire("gush.workflows.#{workflow.id}", ttl) }
      workflow.jobs.each {|job| expire_job(workflow.id, job, ttl) }
    end

    def expire_job(workflow_id, job, ttl=nil)
      ttl = ttl || configuration.ttl
      redis.with { |conn| conn.expire("gush.jobs.#{workflow_id}.#{job.klass}", ttl) }
    end

    def enqueue_job(workflow_id, job)
      job.enqueue!
      persist_job(workflow_id, job)
      queue = job.queue || configuration.namespace

      Gush::Worker.set(queue: queue).perform_later(*[workflow_id, job.name])
    end

    # Make it private end expose locking mechanism here as public API
    def redis
      self.class.connection_pool(configuration)
    end

    private

    def find_job_by_klass_and_id(workflow_id, job_name)
      job_klass, job_id = job_name.split('|')

      redis.with { |conn| conn.hget("gush.jobs.#{workflow_id}.#{job_klass}", job_id) }
    end

    def find_job_by_klass(workflow_id, job_name)
      new_cursor, result = redis.with { |conn| conn.hscan("gush.jobs.#{workflow_id}.#{job_name}", 0, count: 1) }
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
  end
end
