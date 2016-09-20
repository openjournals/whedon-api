require 'json'
require 'octokit'
require 'sinatra'

set :github, Octokit::Client.new(:access_token => ENV['GH_TOKEN'])

# Before we handle the request we extract the issue body to grab the whedon
# command (if present).
before do
  params = JSON.parse(request.env["rack.input"].read)
  # Only work with issues. Halt if there isn't an issue in the JSON
  puts "PARAMS: #{params}"
  halt if params['issue'].nil?
  @action = params['action']

  if @action == 'opened'
    @message = params['issue']['body']
  elsif @action == 'created'
    @message = params['comment']['body']
  end

  @issue_id = params['issue']['number']
  @nwo = params['repository']['full_name']

end

post '/dispatch' do
  if @action == "opened"
    say_hello
    halt
  end

  robawt_respond if @message
end

def say_hello
  respond "HELLO HUMAN, I AM WHEDON"
end

def robawt_respond
  puts "ACTION: #{@action}"
  puts "MESSAGE: #{@message}"
  case @message
  when /@whedon commands/i
    respond "I have all the commands"
  else
    puts "You make no sense human"
  end
end

def respond(comment)
  settings.github.add_comment(@nwo, @issue_id, comment)
end
