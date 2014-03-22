require 'tree'
require 'securerandom'
require 'gush/printable'
require 'gush/metadata'
require 'gush/edge'
require 'gush/node'

module Gush
  class Workflow < Node
    include Gush::Printable
    include Gush::Metadata

    attr_accessor :nodes

    def initialize(name, options = {})
      @name = name
      @nodes = []
      configure unless options[:configure] == false
    end

    def configure
    end

    def find_job(name)
      @nodes.find { |node| node.name == name.to_s || node.class.to_s == name.to_s }
    end

    def finished?
      nodes.all?(&:finished)
    end

    def running?
      nodes.any?(&:enqueued)
    end

    def failed?
      nodes.any?(&:failed)
    end

    def run(klass, deps = {})
      node = klass.new(klass.to_s)

      if deps[:after]
        parent = find_job(deps[:after])
        if parent.nil?
          raise "Job #{deps[:after]} does not exist in the graph. Register it first."
        end
        edge = Edge.new(parent, node)
        parent.connect_to(node)
        node.connect_from(parent)
      end

      if deps[:before]
        child = find_job(deps[:before])
        if child.nil?
          raise "Job #{deps[:before]} does not exist in the graph. Register it first."
        end

        edge = Edge.new(node, child)
        node.connect_to(child)
        child.connect_from(node)
      end

      @nodes << node
    end


    def to_json
      hash = {
        name: @name,
        klass: self.class.to_s,
        nodes: @nodes.map(&:as_json)
      }

      JSON.dump(hash)
    end

    def next_jobs
      @nodes.select(&:can_be_started?)
    end
  end
end
