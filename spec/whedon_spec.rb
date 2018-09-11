require File.expand_path '../spec_helper.rb', __FILE__

describe "Whedon" do
  it "should be alive" do
    get '/heartbeat'
    expect(last_response.body).to include('BOOM boom. BOOM boom. BOOM boom')
    expect(last_response).to be_ok
  end
end
