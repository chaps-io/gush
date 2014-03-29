require 'terminal-table'
require 'colorize'
require 'thor'

module Gush
  class CLI < Thor

    desc "create [WorkflowClass]", "Registers new workflow"
    def create(name)
      require gushfile
      id = SecureRandom.uuid.split("-").first
      workflow = name.constantize.new(id)
      Gush.persist_workflow(workflow, redis)
      puts "Workflow created with id: #{id}"
      puts "Start it with command: gush start #{id}"
    end

    desc "start [workflow_id]", "Starts Workflow with given ID"
    def start(*args)
      require gushfile
      options = {redis: redis}
      id = args.shift
      if args.length > 0
        options[:jobs] = args
      end
      Gush.start_workflow(id, options)
    end

    desc "show [workflow_id]", "Shows details about workflow with given ID"
    def show(workflow_id)
      require gushfile
      workflow = Gush.find_workflow(workflow_id, redis)

      if workflow.nil?
        puts "Workflow not found."
        return
      end

      rows = []
      progress = ""
      if workflow.failed?
        status = "failed".red
        status += "\n"
        status += "#{workflow.nodes.find(&:failed).name} failed".red
      elsif workflow.running?
        status = "running".yellow
        finished = workflow.nodes.count {|job| job.finished }
        total = workflow.nodes.count
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
      rows << [{alignment: :center, value: "jobs"}, workflow.nodes.count]
      rows << :separator
      rows << [{alignment: :center, value: "failed jobs"}, workflow.nodes.count(&:failed).to_s.red]
      rows << :separator
      rows << [{alignment: :center, value: "succeeded jobs"},
        workflow.nodes.count { |j| j.finished && !j.failed }.to_s.green]
      rows << :separator
      rows << [{alignment: :center, value: "enqueued jobs"}, workflow.nodes.count(&:enqueued).to_s.yellow]
      rows << :separator
      rows << [{alignment: :center, value: "remaining jobs"},
        workflow.nodes.count{|j| [j.finished, j.failed, j.enqueued].all? {|b| !b} }]
      rows << :separator
      rows << [{alignment: :center, value: "status"}, status]
      if !progress.empty?
        rows << :separator
        rows << [{alignment: :center, value: "progress"}, progress]
      end
      table = Terminal::Table.new(rows: rows)
      puts table
    end


    desc "list", "Lists all workflows with their statuses"
    def list
      require gushfile
      keys = redis.keys("gush.workflows.*")
      if keys.empty?
        puts "No workflows registered."
        exit
      end
      workflows = redis.mget(*keys).map {|json| Gush.workflow_from_hash(JSON.parse(json)) }
      rows = []
      workflows.each do |workflow|
        progress = ""
        if workflow.failed?
          status = "failed".red
          progress = "#{workflow.nodes.find(&:failed).name} failed"
        elsif workflow.running?
          status = "running".yellow
          finished = workflow.nodes.count {|job| job.finished }
          total = workflow.nodes.count
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

    desc "workers", "Starts Sidekiq workers"
    def workers
      if gushfile.exist?
        Kernel.exec "bundle exec sidekiq -r #{gushfile} -c #{Gush.configuration.concurrency} -v"
      else
        puts "Gushfile not found, please add it to your project"
      end
    end

    desc "viz [WorkflowClass]", "Displays graph, visualising job dependencies"
    def viz(name)
      require gushfile
      workflow = name.constantize.new("start")
      # constant seed to keep colors from changing
      r = Random.new(1235)
      GraphViz.new(:G, type: :digraph, dpi: 200, compound: true) do |g|
        g[:compound] = true
        g[:rankdir] = "LR"
        g[:center] = true
        g.node[:shape] = "box"
        g.node[:style] = "filled"
        g.edge[:dir] = "forward"
        g.edge[:penwidth] = 2
        start = g.start(shape: 'diamond', fillcolor: 'green')
        end_node = g.end(shape: 'diamond', fillcolor: 'red')


        workflow.nodes.each do |job|
          g.add_nodes(job.name)

          if job.incoming_edges.empty?
            g.add_edges(start, job.name)
          end


          if job.outgoing_edges.empty?
            g.add_edges(job.name, end_node)
          else
            job.outgoing_edges.each do |edge|
              g.add_edges(edge.from.name, edge.to.name)
            end
          end
        end

        g.output( :png => "/tmp/graph.png" )
      end

      `xdg-open /tmp/graph.png`
    end

    private
    def gushfile
      gushfile = Pathname.new(FileUtils.pwd).join("Gushfile.rb")
      raise Thor::Error, "Gushfile not found, please add it to your project".colorize(:red) unless gushfile.exist?
      gushfile
    end

    def redis
      @redis ||= Redis.new
    end
  end
end
