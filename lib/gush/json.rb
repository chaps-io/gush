module Gush
  class JSON
    def self.encode(data)
      Oj.dump(data)
    end

    def self.decode(data, options = {symbol_keys: true})
      Oj.load(data, options)
    end
  end
end
