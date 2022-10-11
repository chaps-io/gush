require 'redis'
require 'concurrent-ruby'

module Gush
  class Client
    UUID_REGEXP = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze
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
      # workflow.mark_as_started
      # persist_workflow(workflow)

      jobs = if job_names.empty?
               initial_jobs(workflow.id)
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

    def initial_jobs(workflow_id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (j:Job) WHERE NOT ()-[:OUTGOING]->(j) RETURN j"
        )
      end

      map_nodes_to_jobs(nodes[1])
    end

    def incoming_jobs(workflow_id, job_id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (i:Job)-[:OUTGOING]->(j:Job {id: '#{job_id}'}) RETURN i"
        )
      end

      map_nodes_to_jobs(nodes[1])
    end

    def outgoing_jobs(workflow_id, job_id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (j:Job {id: '#{job_id}'})-[:OUTGOING]->(o:Job) RETURN o"
        )
      end

      map_nodes_to_jobs(nodes[1])
    end

    def all_jobs(workflow_id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (j:Job) RETURN j"
        )
      end

      map_nodes_to_jobs(nodes[1])
    end

    def map_nodes_to_jobs(nodes)
      nodes.map do |node|
        data = node.first.to_h
        Gush::Job.from_properties(data["properties"].to_h)
      end
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
              "MERGE (n:Job #{job_properties(job)})"
            )
          end
        end
      end
    end

    def update_job(workflow_id, job)
      redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (n:Job {id: '#{job.id}'}) SET n += #{job_properties(job)}"
        )
      end
    end

    def job_properties(job)
      props = job.as_properties.map do |key, value|
        "#{key}: '#{value}'"
      end.join(',')

      "{#{props}}"
    end

    def persist_job_dependencies(workflow)
      redis.with do |conn|
        conn.multi do |multi|
          workflow.connections.each do |incoming, outgoing|
            res = multi.call(
              "GRAPH.QUERY",
              "workflow-#{workflow.id}",
              %{
                MATCH (j:Job {id: '#{incoming}'})
                MATCH (o:Job {id: '#{outgoing}'})
                MERGE (j)-[:OUTGOING]->(o)
              }
            )
          end
        end
      end
    end

    def find_job(workflow_id, id_or_name)
      if id_or_name =~ UUID_REGEXP
        find_job_by_id(workflow_id, id_or_name)
      else
        find_job_by_class(workflow_id, id_or_name)
      end
    end

    # TODO use redis graph removal
    def destroy_workflow(workflow)
      redis.with { |conn| conn.del("gush.workflows.#{workflow.id}") }
      workflow.jobs.each {|job| destroy_job(workflow.id, job) }
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
      update_job(workflow_id, job)
      queue = job.queue || configuration.namespace

      Gush::Worker.set(queue: queue).perform_later(*[workflow_id, job.id])
    end

    # Make it private end expose locking mechanism here as public API
    def redis
      self.class.connection_pool(configuration)
    end

    private

    def find_job_by_id(workflow_id, id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (j:Job {id: '#{id}'}) RETURN j LIMIT 1"
        )
      end

      map_nodes_to_jobs(nodes[1]).first
    end

    def find_job_by_class(workflow_id, klass)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          "workflow-#{workflow_id}",
          "MATCH (j:Job {klass: '#{klass}'}) RETURN j LIMIT 1"
        )
      end

      map_nodes_to_jobs(nodes[1]).first
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
