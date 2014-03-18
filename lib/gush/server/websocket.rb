require 'goliath'
require 'goliath/websocket'
require 'goliath/rack/templates'

module Gush
  class Websocket < Goliath::WebSocket

    def on_open(env)
      env.logger.info("WS OPEN")
      env['subscription'] = env.channel.subscribe { |m| env.stream_send(m) }
    end

    def on_message(env, msg)
      env.logger.info("WS MESSAGE: #{msg}")
      env.channel << msg
    end

    def on_close(env)
      env.logger.info("WS CLOSED")
      env.channel.unsubscribe(env['subscription'])
    end

    def on_error(env, error)
      env.logger.error error
    end

    def response(env)
      if env['REQUEST_PATH'] == '/ws'
        super(env)
      else
        [200, {}, slim(:home)]
      end
    end
  end
end
