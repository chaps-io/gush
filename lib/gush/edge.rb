module Gush
  class Edge
    attr_accessor :from, :to

    def initialize(from, to)
      @from = from
      @to = to
    end


    def as_json
      {
        from: from.class.to_s,
        to: to.class.to_s
      }
    end
  end
end
