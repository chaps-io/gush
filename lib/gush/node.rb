require 'gush/edge'

module Gush
  class Node
    attr_accessor :edges, :name, :job_class

    def initialize(name = nil)
      @name = name
      @edges = []
    end

    def connect_to(node)
      edge = Edge.new(self, node)
      @edges << edge
    end

    def connect_from(node)
      edge = Edge.new(node, self)
      @edges << edge
    end

    def outgoing_edges
      @edges.select { |e| e.from == self }
    end

    def incoming_edges
      @edges.select { |e| e.to == self }
    end

    def incoming
      incoming_edges.map(&:from)
    end

    def outgoing
      outgoing_edges.map(&:to)
    end

    def dependencies
      (incoming + incoming.flat_map(&:incoming)).uniq
    end
  end
end
