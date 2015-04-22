module Gush
  class JSON

    def self.encode(data)
      Yajl::Encoder.new.encode(data)
    end

    def self.decode(data, options = {})
      Yajl::Parser.parse(data, options)
    end
  end
end