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
      when "workers"
        start_workers(*args)
      when "clear"
        Sidekiq::Queue.new.clear
      when "viz"
        graph_workflow(*args)
      else
        print_help
      end
    end


    def create(*args)
      require gushfile
      id = SecureRandom.uuid.split("-").first
      workflow = args.first.constantize.new(id)
      Gush.persist_workflow(workflow, redis)
      puts "Workflow created with id: #{id}"
      puts "Start it with command: gush start #{id}"
    end


    def start(*args)
      require gushfile
      options = {redis: redis}
      id = args.shift
      if args.length > 0
        options[:jobs] = args
      end
      Gush.start_workflow(id, options)
    end

    def show(*args)
      require gushfile
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
      rows << [{alignment: :center, value: "failed jobs"}, workflow.jobs.count(&:failed).to_s.red]
      rows << :separator
      rows << [{alignment: :center, value: "succeeded jobs"},
        workflow.jobs.count { |j| j.finished && !j.failed }.to_s.green]
      rows << :separator
      rows << [{alignment: :center, value: "enqueued jobs"}, workflow.jobs.count(&:enqueued).to_s.yellow]
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
      puts
      puts "Workflow tree:"
      puts
      workflow.print_tree
    end

    def list(*args)
      require gushfile
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

    def start_workers(*args)
      if gushfile.exist?
        Kernel.exec "bundle exec sidekiq -r #{gushfile} -v"
      else
        puts "Gushfile not found, please add it to your project"
      end
    end

    def graph_workflow(*args)
      require gushfile
      workflow = args.first.constantize.new("graph-tree")
      GraphViz.new( :G, :type => :digraph, dpi: 200, compound: true ) do |g|
      g[:compound] = true
      g[:rankdir] = "LR"
      g[:center] = true
      g.node[:shape] = "record"

      start = g.start(shape: 'diamond')
      end_node = g.end(shape: 'diamond')


      nodes = workflow.map { |n| n }
      nodes.shift


      g.add_edges(start, nodes.first.name)

      last_node = nil
      nodes.each do |node|
        if node.class <= Gush::Job
          node.children.each do |child|
            last_node = g.add_nodes(child.name) if node.class <= Gush::Job
            if child.class <= Gush::Job
              if node.parent.class.superclass == Gush::Workflow
                g.add_edges(node.name, child.name, ltail: "cluster_#{node.parent.name}")
              else
                g.add_edges(node.name, child.name)
              end
            end
            if child.class.superclass == Gush::Workflow
              if node.parent.class.superclass == Gush::Workflow
                g.add_edges(node.name, child.name, ltail: "cluster_#{node.parent.name}", lhead: "cluster_#{child.name}")
              else
                g.add_edges(node.name, child.name, lhead: "cluster_#{child.name}")
              end
            end
          end
        elsif node.class.superclass == Gush::ConcurrentWorkflow
          cluster = g.add_graph("cluster_#{node.name}")
          cluster[:style] = "dashed,filled"
          cluster[:fillcolor] = "lightgray"
          last_node = g.add_nodes(node.name, style: 'none', color: 'none')
          node.children.each do |child|
            last_node = cluster.add_nodes(child.name)
            if child.class <= Gush::Job
              cluster.add_edges(node.name, child.name, ltail: "cluster_#{node.name}", style: 'invis')
            end
            if child.class.superclass == Gush::Workflow
              cluster.add_edges(node.name, child.name, lhead: "cluster_#{node.name}", ltail: "cluster_#{child.name}")
            end
          end
        end
      end

      g.add_edges(last_node, end_node)

      g.output( :png => "/tmp/graph.png" )
      end

      `shotwell /tmp/graph.png`
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
      puts "gush workers                - starts Sidekiq workers"
      puts "gush help                   - prints help"
      puts
    end
    private

    def gushfile
      gushfile = Pathname.new(FileUtils.pwd).join("Gushfile.rb")
    end

    def redis
      @redis ||= Redis.new
    end
  end
end
