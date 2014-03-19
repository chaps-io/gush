require 'tilt'
require 'slim'
require 'goliath'
require 'goliath/rack/templates'
require 'pry'

Tilt.register :slim, Slim::Template

require 'goliath'
require 'goliath/websocket'
require 'goliath/rack/templates'


module Gush
  class Server < Goliath::WebSocket
    include Goliath::Rack::Templates
    use Goliath::Rack::Params
    use(Rack::Static,
          root: Goliath::Application.app_path("public"),
          urls: ["/favicon.ico", '/stylesheets', '/javascripts', '/images'])

    def on_open(env)
      puts "WS OPEN"
      env['subscription'] = env.channel.subscribe { |m| env.stream_send(m) }
    end

    def on_message(env, msg)
      puts "WS MESSAGE: #{msg}"
      if msg == "workflows.list"
        keys = config['redis'].keys("gush.workflows.*")
        return if keys.empty?
        jsons = config['redis'].mget(*keys)
        workflows = jsons.map {|json| JSON.parse(json) }
        env.channel << {type: 'workflows.list', workflows: workflows }.to_json
      elsif msg == "workflows.add"
        id = SecureRandom.uuid
        workflow = LodgingsWorkflow.new(id)
        Gush.persist_workflow(workflow, config['redis'])
        env.channel << {type: 'workflows.add', id: id, status: true }.to_json
      elsif msg.index("workflows.start.") == 0
        id = msg.split(".").last
        Gush.start_workflow(id, redis: config['redis'])
        send_jobs_list(id)
      elsif msg.index("jobs.list.") == 0
        id = msg.split(".").last
        send_jobs_list(id)
      elsif msg.index("jobs.run.") == 0
        options = msg.split(".")
        run_workflow_job(options[2], options[3])
        send_jobs_list(options[2])
      end
    end

    def on_close(env)
      puts "WS CLOSED"
      env.channel.unsubscribe(env['subscription'])
    end

    def on_error(env, error)
      env.logger.error error
    end

    def response(env)
      if env['REQUEST_PATH'] == '/ws'
        super(env)
      elsif env['REQUEST_PATH'] == '/'
        [200, {}, slim(:home)]
      elsif env['REQUEST_PATH'] == '/workflow'
        workflow = config['redis'].get("gush.workflows.#{env.params["id"]}")
        [200, {}, slim(:workflow, locals: {workflow: JSON.parse(workflow) })]
      end
    end

    def run_workflow_job(workflow_id, job_name)
      workflow = load_workflow(workflow_id)
      job = workflow.find_job(job_name)
      job.class.perform_async(workflow.name, job.name)
      job.enqueue!
    end

    def send_jobs_list(id)
      workflow = load_workflow(id)
      jobs = workflow.jobs.map do |job|
        {name: job.name, workflow_id: id, finished: job.finished, enqueued: job.enqueued, failed: job.failed}
      end
      env.channel << {type: 'jobs.list', jobs: jobs}.to_json
    end

    def load_workflow(id)
      hash = JSON.parse(config['redis'].get("gush.workflows.#{id}"))
      workflow = Gush.tree_from_hash(hash)
    end
  end
end
