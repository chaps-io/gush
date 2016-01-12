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
      expect(graph).to receive(:start).with(shape: 'diamond', fillcolor: '#CFF09E')
      expect(graph).to receive(:end).with(shape: 'diamond', fillcolor: '#F56991')

      expect(graph).to receive(:output).with(png: path.to_s)

      expect(graph).to receive(:add_nodes).with(/Prepare/, label: "Prepare")
      expect(graph).to receive(:add_nodes).with(/FetchFirstJob/, label: "FetchFirstJob")
      expect(graph).to receive(:add_nodes).with(/FetchSecondJob/, label: "FetchSecondJob")
      expect(graph).to receive(:add_nodes).with(/NormalizeJob/, label: "NormalizeJob")
      expect(graph).to receive(:add_nodes).with(/PersistFirstJob/, label: "PersistFirstJob")

      expect(graph).to receive(:add_edges).with(nil, /Prepare/)
      expect(graph).to receive(:add_edges).with(/Prepare/, /FetchFirstJob/)
      expect(graph).to receive(:add_edges).with(/Prepare/, /FetchSecondJob/)
      expect(graph).to receive(:add_edges).with(/FetchFirstJob/, /PersistFirstJob/)
      expect(graph).to receive(:add_edges).with(/FetchSecondJob/, /NormalizeJob/)
      expect(graph).to receive(:add_edges).with(/PersistFirstJob/, /NormalizeJob/)
      expect(graph).to receive(:add_edges).with(/NormalizeJob/, nil)

      expect(GraphViz).to receive(:new).and_yield(graph)

      subject.viz
    end
  end

  describe "#path" do
    it "returns string path to the rendered graph" do
      expect(subject.path).to eq(Pathname.new(Dir.tmpdir).join(filename).to_s)
    end
  end
end
