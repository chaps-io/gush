require 'tree'
require 'securerandom'
require 'gush/metadata'

module Gush
  class Workflow
    include Gush::Metadata

    attr_accessor :nodes

    def initialize(name, options = {})
      @name = name
      @nodes = []
      @dependencies = []

      unless options[:configure] == false
        configure
        create_dependencies
      end
    end

    def configure
    end

    def create_dependencies
      @dependencies.each do |dependency|
        from = find_job(dependency[:from])
        to   = find_job(dependency[:to])

        to.incoming << dependency[:from]
        from.outgoing << dependency[:to]
      end
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
      node = klass.new(name: klass.to_s)
      @nodes << node

      deps_after = [*deps[:after]]
      deps_after.each do |dep|
        @dependencies << {from: dep.to_s, to: klass.to_s }
      end

      deps_before = [*deps[:before]]
      deps_before.each do |dep|
        @dependencies << {from: klass.to_s, to: dep.to_s }
      end
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
      @nodes.select do |job|
        job.can_be_started?(self)
      end
    end
  end
end
