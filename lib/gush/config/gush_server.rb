require 'em-hiredis'

config[:template] = {
  layout_engine: :slim,
  views: Gush.root.join("server/views")
}

config['channel'] = EM::Channel.new

config['redis'] ||= Redis.new

config['pubsub'] ||= EM::Hiredis.connect

config['pubsub'].pubsub.psubscribe('gush.workers.*')
config['pubsub'].pubsub.on(:pmessage)  do |key, channel, json_message|
  message = JSON.parse(json_message)
  if channel == "gush.workers.status"
    ws_message = message.dup
    ws_message["type"] = "jobs.status"
    config['channel'].push(ws_message.to_json)
  end
end
