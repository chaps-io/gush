module Gush
  class Graph
    attr_reader :workflow, :filename, :path, :start, :end_node

    def initialize(workflow, options = {})
      @workflow = workflow
      @filename = options.fetch(:filename, "graph.png")
      @path = options.fetch(:path, Pathname.new(Dir.tmpdir).join(filename))
    end

    def viz
      GraphViz.new(:G, graph_options) do |graph|
        set_node_options!(graph)
        set_edge_options!(graph)

        @start = graph.start(shape: 'diamond', fillcolor: '#CFF09E')
        @end_node = graph.end(shape: 'diamond', fillcolor: '#F56991')

        workflow.jobs.each do |job|
          add_job(graph, job)
        end

        graph.output(png: path)
      end
    end

    def path
      @path.to_s
    end

    private
    def add_job(graph, job)
      name = job.class.to_s
      graph.add_nodes(job.name, label: name)

      if job.incoming.empty?
        graph.add_edges(start, job.name)
      end

      if job.outgoing.empty?
        graph.add_edges(job.name, end_node)
      else
        job.outgoing.each do |id|
          graph.add_edges(job.name, id)
        end
      end
    end

    def set_node_options!(graph)
      node_options.each do |key, value|
        graph.node[key] = value
      end
    end

    def set_edge_options!(graph)
      edge_options.each do |key, value|
        graph.edge[key] = value
      end
    end

    def graph_options
      {
        type: :digraph,
        dpi: 200,
        compound: true,
        rankdir: "LR",
        center: true
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
