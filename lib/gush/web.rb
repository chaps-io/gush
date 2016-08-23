require_relative 'workflow_presenter'

module Gush
  # Hook into *Sidekiq::Web* Sinatra app which adds a new '/workflows' page

  module Web
    VIEW_PATH = File.expand_path('../../../web/views', __FILE__)

    def self.registered(app)
      app.get '/workflows' do
        @workflow_presenters = WorkflowPresenter.build_collection

        erb File.read(File.join(VIEW_PATH, 'workflows.erb'))
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.register(Gush::Web)
Sidekiq::Web.tabs['workflows'] = 'workflows'
Sidekiq::Web.set :locales, Sidekiq::Web.locales << File.expand_path(File.dirname(__FILE__) + "/../../web/locales")
