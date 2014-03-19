require 'gush'
require 'pry'


class Prepare < Gush::Job;  end
class FetchFirstJob < Gush::Job; end
class FetchSecondJob < Gush::Job; end
class PersistFirstJob < Gush::Job; end
class PersistSecondJob < Gush::Job; end
class NormalizeJob < Gush::Job; end


class TestWorkflow < Gush::Workflow
  def configure
    run Prepare

    concurrently do
      run FetchFirstJob
      run FetchSecondJob
    end
    run PersistFirstJob

    run NormalizeJob
  end
end
