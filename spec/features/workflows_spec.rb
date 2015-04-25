require 'spec_helper'


describe "Workflows" do
  it "runs the whole workflow in proper order" do
    flow = TestWorkflow.create
    flow.start!

    expect(Gush::Worker).to have_jobs(flow.id, ["Prepare"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["FetchFirstJob", "FetchSecondJob"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["FetchSecondJob", "PersistFirstJob"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["PersistFirstJob", "NormalizeJob"])

    Gush::Worker.perform_one
    expect(Gush::Worker).to have_jobs(flow.id, ["NormalizeJob"])

    Gush::Worker.perform_one

    expect(Gush::Worker.jobs).to be_empty

    flow = flow.reload
    expect(flow).to be_finished
    expect(flow).to_not be_failed
  end
end