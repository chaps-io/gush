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
      workflow.mark_as_started
      persist_workflow(workflow)

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
          workflow_namespace(workflow_id),
          "MATCH (j:Job) WHERE NOT ()-[:OUTGOING]->(j) RETURN j"
        )
      end

      map_nodes_to_jobs(nodes[1])
    end

    def incoming_jobs(workflow_id, job_id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          workflow_namespace(workflow_id),
          "MATCH (i:Job)-[:OUTGOING]->(j:Job {id: '#{job_id}'}) RETURN i"
        )
      end

      map_nodes_to_jobs(nodes[1])
    end

    def outgoing_jobs(workflow_id, job_id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          workflow_namespace(workflow_id),
          %{
            MATCH (current:Job)-[:OUTGOING]->(o:Job)<-[:OUTGOING]-(parent:Job)
            WHERE
              current.id = '#{job_id}'
              AND o.started_at = ''
              AND o.enqueued_at = ''
              AND o.finished_at = ''
              AND o.failed_at = ''
            RETURN
              o,
              reduce(result = true, n IN collect(parent.finished_at <> '' AND parent.failed_at = '') | n AND result)
          }
        )
      end

      map_nodes_to_jobs(nodes[1].select { |node, done| done == "true" })
    end

    def all_jobs(workflow_id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          workflow_namespace(workflow_id),
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
        prefix = workflow_namespace("")
        conn.call("GRAPH.LIST").filter {|name| name.start_with?(prefix) }.map do |key|
          find_workflow(key.gsub(prefix, ""))
        end
      end
    end

    def find_workflow(id)
      redis.with do |conn|

        unless conn.exists(workflow_namespace(id))
          raise WorkflowNotFound.new("Workflow with given id doesn't exist")
        end

        properties = conn.call(
          "GRAPH.QUERY",
          workflow_namespace(id),
          "MATCH (s:Settings) RETURN s LIMIT 1"
        )[1]

        if properties.none?
          raise WorkflowNotFound.new("Workflow with given id doesn't exist")
        end

        Gush::Workflow.from_properties(properties[0][0][2].last.to_h).tap do |flow|
          flow.jobs = all_jobs(id)
        end
      end
    end

    def persist_workflow(workflow)
      workflow.mark_as_persisted
      persist_workflow_settings(workflow)
      persist_jobs(workflow.id, workflow.jobs)
      persist_job_dependencies(workflow)

      true
    end

    def persist_workflow_settings(workflow)
      redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          workflow_namespace(workflow.id),
          "MERGE (s:Settings) ON CREATE SET s = #{node_properties(workflow)} ON MATCH SET s += #{node_properties(workflow)}"
        )
      end
    end

    def persist_jobs(workflow_id, jobs = workflow.jobs)
      redis.with do |conn|
        conn.multi do |multi|
          jobs.each do |job|
            conn.call(
              "GRAPH.QUERY",
              workflow_namespace(workflow_id),
              "MERGE (j:Job {id: '#{job.id}'}) ON CREATE SET j = #{node_properties(job)} ON MATCH SET j += #{node_properties(job)}"
            )
          end
        end
      end
    end

    def persist_job(workflow_id, job)
      persist_jobs(workflow_id, [job])
    end

    def node_properties(node)
      props = node.as_properties.map do |key, value|
        "#{key}: #{value_to_property(value)}"
      end.compact.join(', ')

      "{#{props}}"
    end

    def value_to_property(value)
      case
      when value.nil?
        "''"
      when value.is_a?(TrueClass)
        "true"
      when value.is_a?(FalseClass)
        "false"
      else
        "'#{value}'"
      end
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
      redis.with { |conn| conn.call("GRAPH.DELETE", workflow_namespace(workflow.id)) }
    end

    def enqueue_job(workflow_id, job)
      job.enqueue!
      persist_job(workflow_id, job)
      queue = job.queue || configuration.namespace

      Gush::Worker.set(queue: queue).perform_later(*[workflow_id, job.id])
    end

    # Make it private end expose locking mechanism here as public API
    def redis
      self.class.connection_pool(configuration)
    end

    private

    def workflow_namespace(workflow_id)
      "#{configuration.namespace}-workflow-#{workflow_id}"
    end

    def find_job_by_id(workflow_id, id)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          workflow_namespace(workflow_id),
          "MATCH (j:Job {id: '#{id}'}) RETURN j LIMIT 1"
        )
      end

      map_nodes_to_jobs(nodes[1]).first
    end

    def find_job_by_class(workflow_id, klass)
      nodes = redis.with do |conn|
        conn.call(
          "GRAPH.QUERY",
          workflow_namespace(workflow_id),
          "MATCH (j:Job {klass: '#{klass}'}) RETURN j LIMIT 1"
        )
      end

      map_nodes_to_jobs(nodes[1]).first
    end
  end
end
