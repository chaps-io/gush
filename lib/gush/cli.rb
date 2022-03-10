# frozen_string_literal: true

require 'terminal-table'
require 'paint'
require 'thor'
require 'launchy'

module Gush
  class CLI < Thor
    class_option :gushfile, desc: "configuration file to use", aliases: "-f"
    class_option :redis, desc: "Redis URL to use", aliases: "-r"
    class_option :namespace, desc: "namespace to run jobs in", aliases: "-n"

    def initialize(*)
      super
      Gush.configure do |config|
        config.gushfile           = options.fetch("gushfile",    config.gushfile)
        config.concurrency        = options.fetch("concurrency", config.concurrency)
        config.redis_url          = options.fetch("redis",       config.redis_url)
        config.namespace          = options.fetch("namespace",   config.namespace)
        config.ttl                = options.fetch("ttl",         config.ttl)
        config.locking_duration   = options.fetch("locking_duration", config.locking_duration)
        config.polling_interval   = options.fetch("polling_interval", config.polling_interval)
      end
      load_gushfile
    end

    desc "create WORKFLOW_CLASS", "Registers new workflow"
    def create(name)
      workflow = client.create_workflow(name)
      puts "Workflow created with id: #{workflow.id}"
      puts "Start it with command: gush start #{workflow.id}"
    end

    desc "start WORKFLOW_ID [ARG ...]", "Starts Workflow with given ID"
    def start(*args)
      id = args.shift
      workflow = client.find_workflow(id)
      client.start_workflow(workflow, args)
    end

    desc "create_and_start WORKFLOW_CLASS [ARG ...]", "Create and instantly start the new workflow"
    def create_and_start(name, *args)
      workflow = client.create_workflow(name)
      client.start_workflow(workflow.id, args)
      puts "Created and started workflow with id: #{workflow.id}"
    end

    desc "stop WORKFLOW_ID", "Stops Workflow with given ID"
    def stop(*args)
      id = args.shift
      client.stop_workflow(id)
    end

    desc "show WORKFLOW_ID", "Shows details about workflow with given ID"
    option :skip_overview, type: :boolean
    option :skip_jobs, type: :boolean
    option :jobs, default: :all
    def show(workflow_id)
      workflow = client.find_workflow(workflow_id)

      display_overview_for(workflow) unless options[:skip_overview]

      display_jobs_list_for(workflow, options[:jobs]) unless options[:skip_jobs]
    end

    desc "rm WORKFLOW_ID", "Delete workflow with given ID"
    def rm(workflow_id)
      workflow = client.find_workflow(workflow_id)
      client.destroy_workflow(workflow)
    end

    desc "list", "Lists all workflows with their statuses"
    def list
      workflows = client.all_workflows
      rows = workflows.map do |workflow|
        [workflow.id, (Time.at(workflow.started_at) if workflow.started_at), workflow.class, {alignment: :center, value: status_for(workflow)}]
      end
      headers = [
        {alignment: :center, value: 'id'},
        {alignment: :center, value: 'started at'},
        {alignment: :center, value: 'name'},
        {alignment: :center, value: 'status'}
      ]
      puts Terminal::Table.new(headings: headers, rows: rows)
    end

    desc "viz {WORKFLOW_CLASS|WORKFLOW_ID}", "Displays graph, visualising job dependencies"
    option :filename, type: :string, default: nil
    option :open, type: :boolean, default: nil
    def viz(class_or_id)
      client

      begin
        workflow = client.find_workflow(class_or_id)
      rescue WorkflowNotFound
        workflow = nil
      end

      unless workflow
        begin
          workflow = class_or_id.constantize.new
        rescue NameError => e
          STDERR.puts Paint["'#{class_or_id}' is not a valid workflow class or id", :red]
          exit 1
        end
      end

      opts = {}

      if options[:filename]
        opts[:filename], opts[:path] = File.split(options[:filename])
      end

      graph = Graph.new(workflow, **opts)
      graph.viz

      if (options[:open].nil? && !options[:filename]) || options[:open]
        Launchy.open Pathname.new(graph.path).realpath.to_s
      end
    end

    private

    def client
      @client ||= Client.new
    end

    def overview(workflow)
      CLI::Overview.new(workflow)
    end

    def display_overview_for(workflow)
      puts overview(workflow).table
    end

    def status_for(workflow)
      overview(workflow).status
    end

    def display_jobs_list_for(workflow, jobs)
      puts overview(workflow).jobs_list(jobs)
    end

    def gushfile
      Gush.configuration.gushfile
    end

    def load_gushfile
      file = client.configuration.gushfile

      unless gushfile.exist?
        raise Thor::Error, Paint["#{file} not found, please add it to your project", :red]
      end

      load file.to_s
    rescue LoadError
      raise Thor::Error, Paint["failed to require #{file}", :red]
    end
  end
end
