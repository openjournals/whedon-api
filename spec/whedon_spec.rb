require 'yaml'
require 'pry'
require File.expand_path '../spec_helper.rb', __FILE__

describe "Whedon" do
  before :all do
    settings_yaml = YAML.load_file("config/settings-#{ENV['RACK_ENV']}.yml")

    settings = Object.new
    allow(settings).to receive(:configs).with(anything()) { OpenStruct.new params } 

    settings_yaml['journals'].each do |journal|
      journal.each do |nwo, params|
        team_id = params["editor_team_id"]
        params["editors"] = github_client.team_members(team_id).collect { |e| e.login }.sort
        settings.configs[nwo] = OpenStruct.new params
      end
    end
  end

  it "should allow accessing the home page" do


    get '/heartbeat'
    expect(last_response).to be_ok
  end
end
