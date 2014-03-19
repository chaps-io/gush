module Gush
  class CLI

    def command(type, *args)
      case type
      when "create"
        create(*args)
      when "start"
        start(*args)
      when "list"
        list(*args)
      when "help"
        print_help
      else
        print_help
      end
    end


    def create(*args)
      id = SecureRandom.uuid.split("-").first
      workflow = LodgingsWorkflow.new(id)
      redis.set("gush.workflows.#{id}", workflow.to_json)
      puts "Workflow created with id: #{id}"
      puts "Start it with command: gush start #{id}"
    end


    def start(*args)
      Gush.start_workflow(args.first, redis)
    end

    def list(*args)
      keys = redis.keys("gush.workflows.*")
      if keys.empty?
        puts "No workflows registered."
        exit
      end

      workflows = redis.mget(*keys).map {|json| Gush.tree_from_hash(JSON.parse(json)) }
      workflows.each do |workflow|
        if workflow.running?
          status = "[running - #{workflow.jobs.count {|job| job.finished }}/#{workflow.jobs.count}]"
        elsif workflow.finished?
          status = "[done]   "
        else
          status = "[pending]"
        end
        puts "(#{workflow.name})#{status} #{workflow.class}"
      end
    end

    def print_help
      puts "Usage:"
      puts
      puts "gush [command] [args]"
      puts
      puts "Available commands:"
      puts
      puts "gush create [WorkflowClass] - registers a new workflow"
      puts "gush start [workflow_id]    - starts a workflow with the given id. id is returned from `gush create`"
      puts "gush list                   - lists all registered workflows and their statuses"
      puts "gush help                   - prints help"
      puts
    end
    private

    def redis
      @redis ||= Redis.new
    end
  end
end
