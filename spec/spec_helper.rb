require 'rack/test'
require 'rspec'
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

ENV['RACK_ENV'] = 'test'

require File.expand_path '../../whedon_api.rb', __FILE__
require File.expand_path '../../workers.rb', __FILE__
require File.expand_path '../support/fake_github.rb', __FILE__
require File.expand_path '../support/fake_joss.rb', __FILE__

module RSpecMixin
  include Rack::Test::Methods
  def app() described_class end

  def json_fixture(file_name)
    File.open(File.dirname(__FILE__) + '/support/fixtures/' + file_name, 'rb').read
  end

  def erb_response(file_name)
    File.open(File.expand_path '../responses/' + file_name, 'rb').read
  end

  def fixture(file_name)
    File.dirname(__FILE__) + '/support/fixtures/' + file_name
  end
end

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:any, /api.github.com/).to_rack(FakeGitHub)
    stub_request(:any, /joss.theoj.org/).to_rack(FakeJoss)

    stub_request(:head, "https://doi.org/10.1038/nmeth.3252").
      with(
       headers: {
      'Accept'=>'*/*',
      'User-Agent'=>'Faraday v0.14.0'
       }).to_return(status: 301, body: "", headers: {})

    stub_request(:head, "https://doi.org/10.1038/INVALID").
      with(
       headers: {
        'Accept'=>'*/*',
        'User-Agent'=>'Faraday v0.14.0'
       }).to_return(status: 404, body: "", headers: {})

  end

  config.include RSpecMixin
end
