require 'terminal-table'
require 'colorize'
require 'thor'
require 'launchy'
require 'sidekiq'
require 'sidekiq/api'

module Gush
  class CLI < Thor
    class_option :gushfile, desc: "configuration file to use", aliases: "-f"
    class_option :concurrency, desc: "concurrency setting for Sidekiq", aliases: "-c"
    class_option :redis, desc: "Redis URL to use", aliases: "-r"
    class_option :namespace, desc: "namespace to run jobs in", aliases: "-n"
    class_option :env, desc: "Sidekiq environment", aliases: "-e"

    def initialize(*)
      super
      Gush.configure do |config|
        config.gushfile    = options.fetch("gushfile",    config.gushfile)
        config.concurrency = options.fetch("concurrency", config.concurrency)
        config.redis_url   = options.fetch("redis",       config.redis_url)
        config.namespace   = options.fetch("namespace",   config.namespace)
        config.environment = options.fetch("environment", config.environment)
      end
    end

    desc "create [WorkflowClass]", "Registers new workflow"
    def create(name)
      workflow = client.create_workflow(name)
      puts "Workflow created with id: #{workflow.id}"
      puts "Start it with command: gush start #{workflow.id}"
    rescue
      puts "Workflow not found."
    end

    desc "start [workflow_id]", "Starts Workflow with given ID"
    def start(*args)
      id = args.shift
      client.start_workflow(id, args)
    rescue WorkflowNotFound
      puts "Workflow not found."
    rescue DependencyLevelTooDeep
      puts "Dependency level too deep. Perhaps you have a dependency cycle?"
    end

    desc "create_and_start [WorkflowClass]", "Create and instantly start the new workflow"
    def create_and_start(name, *args)
      workflow = client.create_workflow(name)
      client.start_workflow(workflow.id, args)
      puts "Created and started workflow with id: #{workflow.id}"
    rescue WorkflowNotFound
      puts "Workflow not found."
    rescue DependencyLevelTooDeep
      puts "Dependency level too deep. Perhaps you have a dependency cycle?"
    end

    desc "stop [workflow_id]", "Stops Workflow with given ID"
    def stop(*args)
      id = args.shift
      client.stop_workflow(id)
    rescue WorkflowNotFound
      puts "Workflow not found."
    end

    desc "clear", "Clears all jobs from Sidekiq queue"
    def clear
      Sidekiq::Queue.new(client.configuration.namespace).clear
    end

    desc "show [workflow_id]", "Shows details about workflow with given ID"
    option :skip_overview, type: :boolean
    option :skip_jobs, type: :boolean
    option :jobs, default: :all
    def show(workflow_id)
      workflow = client.find_workflow(workflow_id)

      display_overview_for(workflow) unless options[:skip_overview]

      display_jobs_list_for(workflow, options[:jobs]) unless options[:skip_jobs]
    rescue WorkflowNotFound
      puts "Workflow not found."
    end

    desc "rm [workflow_id]", "Delete workflow with given ID"
    def rm(workflow_id)
      workflow = client.find_workflow(workflow_id)
      client.destroy_workflow(workflow)
    rescue WorkflowNotFound
      puts "Workflow not found."
    end

    desc "list", "Lists all workflows with their statuses"
    def list
      workflows = client.all_workflows
      rows = workflows.map do |workflow|
        [workflow.id, workflow.class, {alignment: :center, value: status_for(workflow)}]
      end
      headers = [
        {alignment: :center, value: 'id'},
        {alignment: :center, value: 'name'},
        {alignment: :center, value: 'status'}
      ]
      puts Terminal::Table.new(headings: headers, rows: rows)
    end

    desc "workers", "Starts Sidekiq workers"
    def workers
      config = client.configuration
      Kernel.exec "bundle exec sidekiq -r #{config.gushfile} -c #{config.concurrency} -q #{config.namespace} -e #{config.environment} -v"
    end

    desc "viz [WorkflowClass]", "Displays graph, visualising job dependencies"
    def viz(name)
      client
      workflow = name.constantize.new("start")
      Launchy.open Graph.new(workflow).path
    end

    private

    def client
      @client ||= Client.new
    end

    def display_overview_for(workflow)
      rows = []
      columns  = {
        "id" => workflow.id,
        "name" => workflow.class.to_s,
        "jobs" => workflow.nodes.count,
        "failed jobs" => workflow.nodes.count(&:failed?).to_s.red,
        "succeeded jobs" => workflow.nodes.count(&:succeeded?).to_s.green,
        "enqueued jobs" => workflow.nodes.count(&:enqueued?).to_s.yellow,
        "running jobs" => workflow.nodes.count(&:running?).to_s.blue,
        "remaining jobs" => workflow.nodes.count{|j| [j.finished, j.failed, j.enqueued].all? {|b| !b} },
        "status" => status_for(workflow)
      }

      columns.each_pair do |name, value|
        rows << [{alignment: :center, value: name}, value]
        rows << :separator if name != "status"
      end

      puts Terminal::Table.new(rows: rows)
    end

    def status_for(workflow)
      if workflow.failed?
        status = "failed".light_red
        status += "\n#{workflow.nodes.find(&:failed).name} failed"
      elsif workflow.running?
        status = "running".yellow
        finished = workflow.nodes.count {|job| job.finished }
        total = workflow.nodes.count
        status += "\n#{finished}/#{total} [#{(finished*100)/total}%]"
      elsif workflow.finished?
        status = "done".green
      elsif workflow.stopped?
        status = "stopped".red
      else
        status = "pending".light_white
      end
    end

    def display_jobs_list_for(workflow, jobs)
      puts "\nJobs list:\n"

      jobs_by_type(workflow, jobs).each do |job|
        name = job.name
        puts case
        when job.failed?
          "[✗] #{name.red}"
        when job.finished?
          "[✓] #{name.green}"
        when job.enqueued?
          "[•] #{name.yellow}"
        when job.running?
          "[•] #{name.blue}"
        else
          "[ ] #{name}"
        end
      end
    end

    def jobs_by_type(workflow, type)
      jobs = workflow.nodes.sort_by do |job|
        case
        when job.failed?
          0
        when job.finished?
          1
        when job.enqueued?
          2
        when job.running?
          3
        else
          4
        end
      end

      jobs.select!{|j| j.public_send("#{type}?") } unless type == :all
      jobs
    end

    def gushfile
      Pathname.pwd.join(options[:gushfile])
    end
  end
end
