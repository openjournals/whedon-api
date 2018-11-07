require File.expand_path '../spec_helper.rb', __FILE__

describe WhedonApi do
  it "should be alive" do
    get '/heartbeat'
    expect(last_response.body).to include('BOOM boom. BOOM boom. BOOM boom')
    expect(last_response).to be_ok
  end

  context "settings" do
    let(:settings) { app.settings.journals }

    before :each do
      get '/heartbeat'
    end

    it "should initalize setting properly" do
      expect(settings.size).to eq(1)
      %w{editor_team_id papers reviewers reviewers_signup site_host doi_prefix
      journal_alias journal_launch_date site_name donate_url site_api_key
      editors}.each do |key|
        expect(settings.first['openjournals/joss-reviews-testing']).to have_key(key)
      end
    end

    it "should initialize GitHub team properly" do
      expect(settings.first['openjournals/joss-reviews-testing']['editors']).to include('arfon')
    end
  end
end
