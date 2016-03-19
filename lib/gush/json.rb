module Gush
  class JSON
    def self.encode(data, options = {})
      MultiJson.dump(data, options)
    end

    def self.decode(data, options = {})
      MultiJson.load(data, options)
    end
  end
end
