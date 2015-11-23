module Gush
  class Client
    attr_reader :configuration

    def initialize(config = Gush.configuration)
      @configuration = config
      @sidekiq = build_sidekiq
      @redis = build_redis
    end

    def configure
      yield configuration
      @sidekiq = build_sidekiq
      @redis = build_redis
    end

    def create_workflow(name)
      begin
        flow = name.constantize.new
        flow.save
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

    def next_free_job_id(workflow_id,job_class)
      id = nil
      loop do
        id = SecureRandom.uuid
        break if !redis.exists("gush.jobs.#{workflow_id}.#{job_class}-#{id}")
      end

      "#{job_class}-#{id}"
    end

    def next_free_workflow_id
      id = nil
      loop do
        id = SecureRandom.uuid
        break if !redis.exists("gush.workflow.#{id}.")
      end

      id
    end

    def all_workflows
      redis.keys("gush.workflows.*").map do |key|
        id = key.sub("gush.workflows.", "")
        find_workflow(id)
      end
    end

    def find_workflow(id)
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

    def persist_workflow(workflow)
      redis.set("gush.workflows.#{workflow.id}", workflow.to_json)
      workflow.jobs.each {|job| persist_job(workflow.id, job) }
      workflow.mark_as_persisted
      true
    end

    def persist_job(workflow_id, job)
      redis.set("gush.jobs.#{workflow_id}.#{job.class.to_s}", job.to_json)
    end

    def load_job(workflow_id, job_id)
      workflow = find_workflow(workflow_id)
      data = redis.get("gush.jobs.#{workflow_id}.#{job_id}")
      return nil if data.nil?
      data = Gush::JSON.decode(data, symbolize_keys: true)
      Gush::Job.from_hash(workflow, data)
    end

    def destroy_workflow(workflow)
      redis.del("gush.workflows.#{workflow.id}")
      workflow.jobs.each {|job| destroy_job(workflow.id, job) }
    end

    def destroy_job(workflow_id, job)
      redis.del("gush.jobs.#{workflow_id}.#{job.class.to_s}")
    end

    def worker_report(message)
      report("gush.workers.status", message)
    end

    def workflow_report(message)
      report("gush.workflows.status", message)
    end

    def enqueue_job(workflow_id, job)
      job.enqueue!
      persist_job(workflow_id, job)

      sidekiq.push(
        'class' => Gush::Worker,
        'queue' => configuration.namespace,
        'args'  => [workflow_id, job.name]
      )
    end

    private

    attr_reader :sidekiq, :redis

    def workflow_from_hash(hash, nodes = nil)
      flow = hash[:klass].constantize.new
      flow.stopped = hash.fetch(:stopped, false)
      flow.id = hash[:id]

      (nodes || hash[:nodes]).each do |node|
        flow.jobs << Gush::Job.from_hash(flow, node)
      end

      flow
    end

    def report(key, message)
      redis.publish(key, Gush::JSON.encode(message))
    end


    def build_sidekiq
      Sidekiq::Client.new(connection_pool)
    end

    def build_redis
      Redis.new(url: configuration.redis_url)
    end

    def connection_pool
      ConnectionPool.new(size: configuration.concurrency, timeout: 1) { build_redis }
    end
  end
end
