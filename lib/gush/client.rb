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

    def next_free_job_id(workflow_id,job_klass)
      job_identifier = nil
      loop do
        id = SecureRandom.uuid
        job_identifier = "#{job_klass}-#{id}"
        available = connection_pool.with do |redis|
          !redis.exists("gush.jobs.#{workflow_id}.#{job_identifier}")
        end

        break if available
      end

      job_identifier
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
        redis.keys("gush.workflows.*").map do |key|
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
          keys = redis.keys("gush.jobs.#{id}.*")
          nodes = redis.mget(*keys).map { |json| Gush::JSON.decode(json, symbolize_keys: true) }
          workflow_from_hash(hash, nodes)
        else
          raise WorkflowNotFound.new("Workflow with given id doesn't exist")
        end
      end
    end

    def persist_workflow(workflow)
      connection_pool.with do |redis|
        redis.set("gush.workflows.#{workflow.id}", workflow.to_json)
      end

      workflow.jobs.each {|job| persist_job(workflow.id, job) }
      workflow.mark_as_persisted
      true
    end

    def persist_job(workflow_id, job)
      connection_pool.with do |redis|
        redis.set("gush.jobs.#{workflow_id}.#{job.name}", job.to_json)
      end
    end

    def find_job(workflow_id, job_id)
      job_name_match = /(?<klass>\w*[^-])-(?<identifier>.*)/.match(job_id)
      hypen = '-' if job_name_match.nil?

      keys = connection_pool.with do |redis|
        redis.keys("gush.jobs.#{workflow_id}.#{job_id}#{hypen}*")
      end

      return nil if keys.nil?

      data = connection_pool.with do |redis|
        redis.get(keys.first)
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
        redis.del("gush.jobs.#{workflow_id}.#{job.name}")
      end
    end

    def enqueue_job(workflow_id, job)
      job.enqueue!
      persist_job(workflow_id, job)

      Gush::Worker.set(queue: configuration.namespace).perform_later(*[workflow_id, job.name])
    end

    private

    def workflow_from_hash(hash, nodes = nil)
      flow = hash[:klass].constantize.new(*hash[:arguments])
      flow.jobs = []
      flow.stopped = hash.fetch(:stopped, false)
      flow.id = hash[:id]

      (nodes || hash[:nodes]).each do |node|
        flow.jobs << Gush::Job.from_hash(node)
      end

      flow
    end

    def build_redis
      Redis.new(url: configuration.redis_url)
    end

    def connection_pool
      @connection_pool ||= ConnectionPool.new(size: configuration.concurrency, timeout: 1) { build_redis }
    end
  end
end
