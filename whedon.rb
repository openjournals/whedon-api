require 'json'
require 'sinatra'

# Before we handle the request we extract the issue body to grab the whedon
# command (if present).
before do
  params = JSON.parse(request.env["rack.input"].read)
  # Only work with issues. Halt if there isn't an issue in the JSON
  puts "PARAMS: #{params}"
  halt if params['issue'].nil?
  @action = params['action']
  @message = params['issue']['body']
end

post '/dispatch' do
  say_hello if @action == "opened"
  robawt_respond if @message
end

def say_hello
  puts "HELLO HUMAN, I AM WHEDON"
end

def robawt_respond
  puts "ACTION: #{@action}"
  puts "MESSAGE: #{@message}"
  case @message
  when /commands/i
    puts "I have all the commands"
  else
    puts "You make no sense human"
  end
end
