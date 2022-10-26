# frozen_string_literal: true

require 'tmpdir'

module Gush
  class Graph
    attr_reader :workflow, :filename, :path, :start_node, :end_node

    def initialize(workflow, options = {})
      @workflow = workflow
      @filename = options.fetch(:filename, "graph.png")
      @path = options.fetch(:path, Pathname.new(Dir.tmpdir).join(filename))
    end

    def viz
      @graph = Graphviz::Graph.new(**graph_options)
      @start_node = add_node('start', shape: 'diamond', fillcolor: '#CFF09E')
      @end_node = add_node('end', shape: 'diamond', fillcolor: '#F56991')

      # First, create nodes for all jobs
      @job_name_to_node_map = {}
      workflow.jobs.each do |job|
        add_job_node(job)
      end

      # Next, link up the jobs with edges
      link_job_edges(workflow)

      format = 'png'
      file_format = path.split('.')[-1]
      format = file_format if file_format.length == 3

      Graphviz::output(@graph, path: path, format: format)
    end

    def path
      @path.to_s
    end

    private

    def add_node(name, **specific_options)
      @graph.add_node(name, **node_options.merge(specific_options))
    end

    def add_job_node(job)
      @job_name_to_node_map[job.id] = add_node(job.id, label: node_label_for_job(job))
    end

    def link_job_edges(workflow)
      workflow.connections.each do |in_id, out_id|
        in_job = @job_name_to_node_map[in_id]
        out_job = @job_name_to_node_map[out_id]
        in_job.connect(out_job, **edge_options)
      end

      root_jobs = workflow.jobs.map(&:id) - workflow.connections.map(&:last)
      leaf_jobs = workflow.jobs.map(&:id) - workflow.connections.map(&:first)

      root_jobs.each do |id|
        @start_node.connect(@job_name_to_node_map[id], **edge_options)
      end

      leaf_jobs.each do |id|
        @job_name_to_node_map[id].connect(@end_node, **edge_options)
      end
    end

    def node_label_for_job(job)
      job.class.to_s
    end

    def graph_options
      {
          dpi: 200,
          compound: true,
          rankdir: "LR",
          center: true,
          format: 'png'
      }
    end

    def node_options
      {
        shape: "ellipse",
        style: "filled",
        color: "#555555",
        fillcolor: "white"
      }
    end

    def edge_options
      {
        dir: "forward",
        penwidth: 1,
        color: "#555555"
      }
    end
  end
end
