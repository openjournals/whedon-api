require 'json'
require 'sinatra'

before do
  params = JSON.parse(request.env["rack.input"].read)
  @message = params['body']
end

post '/dispatch' do
  puts @message
  case @message
  when /commands/i
    puts "I have all the commands"
  else
    puts "You make no sense human"
  end
end
