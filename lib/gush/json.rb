require "oj"

module Gush
  class JSON
    def self.encode(data, options = {mode: :compat})
      Oj.dump(data, options)
    end

    def self.decode(data, options = {mode: :compat, symbol_keys: true})
      Oj.load(data, options)
    end
  end
end
