require 'spec_helper'

describe Gush::Graph do
  subject { described_class.new(TestWorkflow.create) }
  let(:filename) { "graph.png" }

  describe "#viz" do
    it "runs GraphViz to render graph" do
      node = double("node", :[]= => true)
      edge = double("edge", :[]= => true)
      graph = double("graph", node: node, edge: edge)
      path = Pathname.new(Dir.tmpdir).join(filename)

      expect(Graphviz::Graph).to receive(:new).and_return(graph)

      node_start = double('start')
      node_end = double('end')
      node_prepare = double('Prepare')
      node_fetch_first_job = double('FetchFirstJob')
      node_fetch_second_job = double('FetchSecondJob')
      node_normalize_job = double('NormalizeJob')
      node_persist_first_job = double('PersistFirstJob')

      expect(graph).to receive(:add_node).with('start', {shape: 'diamond', fillcolor: '#CFF09E', color: "#555555", style: 'filled'}).and_return(node_start)
      expect(graph).to receive(:add_node).with('end', {shape: 'diamond', fillcolor: '#F56991', color: "#555555", style: 'filled'}).and_return(node_end)

      standard_options = {:color=>"#555555", :fillcolor=>"white", :label=>"Prepare", :shape=>"ellipse", :style=>"filled"}

      expect(graph).to receive(:add_node).with(/Prepare/, standard_options.merge(label: "Prepare")).and_return(node_prepare)
      expect(graph).to receive(:add_node).with(/FetchFirstJob/, standard_options.merge(label: "FetchFirstJob")).and_return(node_fetch_first_job)
      expect(graph).to receive(:add_node).with(/FetchSecondJob/, standard_options.merge(label: "FetchSecondJob")).and_return(node_fetch_second_job)
      expect(graph).to receive(:add_node).with(/NormalizeJob/, standard_options.merge(label: "NormalizeJob")).and_return(node_normalize_job)
      expect(graph).to receive(:add_node).with(/PersistFirstJob/, standard_options.merge(label: "PersistFirstJob")).and_return(node_persist_first_job)

      edge_options = {
          dir: "forward",
          penwidth: 1,
          color: "#555555"
      }

      expect(node_start).to receive(:connect).with(node_prepare, **edge_options)
      expect(node_prepare).to receive(:connect).with(node_fetch_first_job, **edge_options)
      expect(node_prepare).to receive(:connect).with(node_fetch_second_job, **edge_options)
      expect(node_fetch_first_job).to receive(:connect).with(node_persist_first_job, **edge_options)
      expect(node_fetch_second_job).to receive(:connect).with(node_normalize_job, **edge_options)
      expect(node_persist_first_job).to receive(:connect).with(node_normalize_job, **edge_options)
      expect(node_normalize_job).to receive(:connect).with(node_end, **edge_options)

      expect(graph).to receive(:dump_graph).and_return(nil)

      subject.viz
    end
  end

  describe "#path" do
    it "returns string path to the rendered graph" do
      expect(subject.path).to eq(Pathname.new(Dir.tmpdir).join(filename).to_s)
    end
  end
end
