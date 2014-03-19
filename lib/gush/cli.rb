require 'terminal-table'
require 'colorize'

module Gush
  class CLI

    def command(type, *args)
      case type
      when "create"
        create(*args)
      when "start"
        start(*args)
      when "show"
        show(*args)
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
      Gush.persist_workflow(workflow, redis)
      puts "Workflow created with id: #{id}"
      puts "Start it with command: gush start #{id}"
    end


    def start(*args)
      Gush.start_workflow(args.first, redis: redis)
    end

    def show(*args)
      workflow = Gush.find_workflow(args.first, redis)

      if workflow.nil?
        puts "Workflow not found."
        return
      end

      rows = []
      progress = ""
      if workflow.failed?
        status = "failed".red
        status += "\n"
        status += "#{workflow.jobs.find(&:failed).name} failed".red
      elsif workflow.running?
        status = "running".yellow
        finished = workflow.jobs.count {|job| job.finished }
        total = workflow.jobs.count
        progress = "#{finished}/#{total} [#{(finished*100)/total}%]"
      elsif workflow.finished?
        status = "done".green
      else
        status = "pending".light_white
      end

      rows << [{alignment: :center, value: "id"}, workflow.name]
      rows << :separator
      rows << [{alignment: :center, value: "name"}, workflow.class.to_s]
      rows << :separator
      rows << [{alignment: :center, value: "jobs"}, workflow.jobs.count]
      rows << :separator
      rows << [{alignment: :center, value: "failed jobs"}, workflow.jobs.count(&:failed)]
      rows << :separator
      rows << [{alignment: :center, value: "succeeded jobs"},
        workflow.jobs.count { |j| j.finished && !j.failed }]
      rows << :separator
      rows << [{alignment: :center, value: "enqueued jobs"}, workflow.jobs.count(&:enqueued)]
      rows << :separator
      rows << [{alignment: :center, value: "remaining jobs"},
        workflow.jobs.count{|j| [j.finished, j.failed, j.enqueued].all? {|b| !b} }]
      rows << :separator
      rows << [{alignment: :center, value: "status"}, status]
      if !progress.empty?
        rows << :separator
        rows << [{alignment: :center, value: "progress"}, progress]
      end
      table = Terminal::Table.new(rows: rows)
      puts table
    end

    def list(*args)
      keys = redis.keys("gush.workflows.*")
      if keys.empty?
        puts "No workflows registered."
        exit
      end
      workflows = redis.mget(*keys).map {|json| Gush.tree_from_hash(JSON.parse(json)) }
      rows = []
      workflows.each do |workflow|
        progress = ""
        if workflow.failed?
          status = "failed".red
          progress = "#{workflow.jobs.find(&:failed).name} failed"
        elsif workflow.running?
          status = "running".yellow
          finished = workflow.jobs.count {|job| job.finished }
          total = workflow.jobs.count
          progress = "#{finished}/#{total} [#{(finished*100)/total}%]"
        elsif workflow.finished?
          status = "done".green
        else
          status = "pending".light_white
        end
        rows << [workflow.name, workflow.class, {alignment: :center, value: status}, progress]
      end
      headers = [
        {alignment: :center, value: 'id'},
        {alignment: :center, value: 'name'},
        {alignment: :center, value: 'status'},
        {alignment: :center, value: 'progress'}
      ]
      table = Terminal::Table.new(headings: headers, rows: rows)
      puts table
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
      puts "gush show [workflow_id]     - shows details about the given workflow"
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
