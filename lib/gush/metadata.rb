module Gush
  module Metadata

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def metadata(params = {})
        @metadata = (@metadata || {}).merge(params)
      end
    end

    def name
      metadata[:name] || @name
    end

    private

    def metadata
      self.class.metadata
    end
  end
end
