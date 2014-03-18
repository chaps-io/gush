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
  puts "[#{key}] #{channel}: #{message}"

  if channel == "gush.workers.status"
    #hash = JSON.parse(config['redis'].get("gush.workflows.#{message["workflow_id"]}"))
    #workflow = Gush.tree_from_hash(hash)
    #job = workflow.find_job(message["job"])
    #if message["status"] == "finished"
    #  job.finish!
    #elsif message["status"] == "failed"
    #  job.fail!
    #end
    #config['redis'].set("gush.workflows.#{message["workflow_id"]}", workflow.to_json)
    ws_message = message.dup
    ws_message["type"] = "jobs.status"
    config['channel'].push(ws_message.to_json)
    #if message["status"] == "finished"
      #Gush.start_workflow(message["workflow_id"], config['redis'])
    #end
  end
end
