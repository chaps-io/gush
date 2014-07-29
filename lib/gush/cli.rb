require 'terminal-table'
require 'colorize'
require 'thor'
require 'launchy'
require 'sidekiq'
require 'sidekiq/api'

module Gush
  class CLI < Thor

    desc "create [WorkflowClass]", "Registers new workflow"
    def create(name)
      workflow = Gush.create_workflow(name, redis)
      puts "Workflow created with id: #{workflow.id}"
      puts "Start it with command: gush start #{workflow.id}"
      return workflow.id
    end

    desc "start [workflow_id]", "Starts Workflow with given ID"
    def start(*args)
      options = {redis: redis}
      id = args.shift
      if args.length > 0
        options[:jobs] = args
      end
      Gush.start_workflow(id, options)
    end

    desc "create_and_start [WorkflowClass]", "Create and instantly start the new workflow"
    def create_and_start(name)
      id = create(name)
      start(id)
    end

    desc "stop [workflow_id]", "Stops Workflow with given ID"
    def stop(*args)
      options = {redis: redis}
      id = args.shift
      Gush.stop_workflow(id, options)
    end

    desc "clear", "Clears all jobs from Sidekiq queue"
    def clear
      Sidekiq::Queue.new(Gush.configuration.namespace).clear
    end

    desc "show [workflow_id]", "Shows details about workflow with given ID"
    option :skip_overview, type: :boolean
    option :skip_jobs, type: :boolean
    option :jobs, default: :all
    def show(workflow_id)
      workflow = Gush.find_workflow(workflow_id, redis)

      display_overview_for(workflow) unless options[:skip_overview]

      display_jobs_list_for(workflow, options[:jobs]) unless options[:skip_jobs]
    rescue WorkflowNotFoundError
      puts "Workflow not found."
    end

    desc "list", "Lists all workflows with their statuses"
    def list
      keys = redis.keys("gush.workflows.*")
      if keys.empty?
        puts "No workflows registered."
        exit
      end
      workflows = keys.map do |key|
        id = key.sub("gush.workflows.", "")
        Gush.find_workflow(id, redis)
      end
      rows = []
      workflows.each do |workflow|
        rows << [workflow.id, workflow.class, {alignment: :center, value: status_for(workflow)}]
      end
      headers = [
        {alignment: :center, value: 'id'},
        {alignment: :center, value: 'name'},
        {alignment: :center, value: 'status'}
      ]
      table = Terminal::Table.new(headings: headers, rows: rows)
      puts table
    end

    desc "workers", "Starts Sidekiq workers"
    def workers
      config = Gush.configuration
      Kernel.exec "bundle exec sidekiq -r #{Gush.gushfile} -c #{config.concurrency} -q #{config.namespace} -v"
    end

    desc "viz [WorkflowClass]", "Displays graph, visualising job dependencies"
    def viz(name)
      workflow = name.constantize.new("start")
      GraphViz.new(:G, type: :digraph, dpi: 200, compound: true) do |g|
        g[:compound] = true
        g[:rankdir] = "LR"
        g[:center] = true
        g.node[:shape] = "ellipse"
        g.node[:style] = "filled"
        g.node[:color] = "#555555"
        g.node[:fillcolor] = "white"
        g.edge[:dir] = "forward"
        g.edge[:penwidth] = 1
        g.edge[:color] = "#555555"
        start = g.start(shape: 'diamond', fillcolor: '#CFF09E')
        end_node = g.end(shape: 'diamond', fillcolor: '#F56991')


        workflow.nodes.each do |job|
          name = job.class.to_s
          g.add_nodes(name)

          if job.incoming.empty?
            g.add_edges(start, name)
          end


          if job.outgoing.empty?
            g.add_edges(name, end_node)
          else
            job.outgoing.each do |out|
              g.add_edges(name, out)
            end
          end
        end

        g.output(png: Pathname.new(Dir.tmpdir).join("graph.png"))
      end

      Launchy.open(Pathname.new(Dir.tmpdir).join("graph.png").to_s)
    end

    private

    def redis
      @redis ||= Redis.new
    end

    def display_overview_for(workflow)
      rows = []
      columns  = {
        "id" => workflow.id,
        "name" => workflow.class.to_s,
        "jobs" => workflow.nodes.count,
        "failed jobs" => workflow.nodes.count(&:failed?).to_s.red,
        "succeeded jobs" => workflow.nodes.count(&:succeeded?).to_s.green,
        "enqueued jobs" => workflow.nodes.count(&:running?).to_s.yellow,
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
        status = "failed".red
        status += "\n#{workflow.nodes.find(&:failed).name} failed"
      elsif workflow.running?
        status = "running".yellow
        finished = workflow.nodes.count {|job| job.finished }
        total = workflow.nodes.count
        status += "\n#{finished}/#{total} [#{(finished*100)/total}%]"
      elsif workflow.finished?
        status = "done".green
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
        when job.running?
          "[•] #{name.yellow}"
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
        when job.running?
          2
        else
          3
        end
      end

      jobs.select!{|j| j.public_send("#{type}?") } unless type == :all
      jobs
    end
  end
end
