require 'json'
require 'sinatra'

post '/dispatch' do
  params = JSON.parse(request.env["rack.input"].read)
  puts "I HAVE PARAMS!"
  puts params
end
