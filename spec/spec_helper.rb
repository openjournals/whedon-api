require 'rack/test'
require 'rspec'
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

ENV['RACK_ENV'] = 'test'

require File.expand_path '../../whedon_api.rb', __FILE__
require File.expand_path '../support/fake_github.rb', __FILE__

module RSpecMixin
  include Rack::Test::Methods
  def app() described_class end

  def json_fixture(file_name)
    File.open(File.dirname(__FILE__) + '/support/fixtures/' + file_name, 'rb').read
  end
end

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:any, /api.github.com/).to_rack(FakeGitHub)
  end

  config.include RSpecMixin
end
