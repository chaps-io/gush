module Gush
  class IndexWorkflowsByCreatedAtAndExpiresAt < Gush::Migration
    def self.version
      1
    end

    def up
      redis.scan_each(match: "gush.workflows.*").map do |key|
        id = key.sub("gush.workflows.", "")
        workflow = client.find_workflow(id)

        ttl = redis.ttl(key)
        redis.persist(key)
        workflow.jobs.each { |job| redis.persist("gush.jobs.#{id}.#{job.klass}") }

        client.persist_workflow(workflow)
        client.expire_workflow(workflow, ttl.positive? ? ttl : -1)
      end
    end
  end
end
