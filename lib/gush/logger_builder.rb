module Gush
  LoggerBuilder = Struct.new(:job) do
    def build
      NullLogger.new
    end
  end
end
