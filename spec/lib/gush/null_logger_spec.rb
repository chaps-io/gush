require 'spec_helper'

describe Gush::NullLogger do
  let(:logger) { Gush::NullLogger.new }

  it 'responds to logger methods and ignores them' do
    [:info, :debug, :error, :fatal].each do |method|
      logger.send(method, "message")
    end
  end

  it 'works when block with message is passed' do
    logger.info("progname") { "message" }
  end
end
