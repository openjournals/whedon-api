require 'json'
require 'sinatra'

before do
  params = JSON.parse(request.env["rack.input"].read)
  # Only work with issues
  halt if params['issue'].nil?
  @message = params['issue']['body']
end

post '/dispatch' do
  case @message
  when /commands/i
    puts "I have all the commands"
  else
    puts "You make no sense human"
  end
end
