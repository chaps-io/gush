module Gush
  class JSON
    def self.encode(data)
      MultiJson.dump(data)
    end

    def self.decode(data, options = {symbolize_keys: true})
      MultiJson.load(data, options)
    end
  end
end
