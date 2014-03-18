require_relative '../gush'
require_relative '../../workflows/workflows'
require_relative 'server/server'
server = Goliath::Server.new
server.options = {
  config: Gush.root.join('server/config')
}

#server.start
Goliath::Application.run!
