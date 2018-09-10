require 'rack/test'
require 'rspec'

ENV['RACK_ENV'] = 'test'

require File.expand_path '../../whedon.rb', __FILE__

module RSpecMixin
  include Rack::Test::Methods
  def app() Sinatra::Application end
end

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:any, /api.github.com/).to_rack(FakeGitHub)
  end

  config.include RSpecMixin
end
