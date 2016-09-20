require 'json'
require 'octokit'
require 'sinatra'

set :github, Octokit::Client.new(:access_token => ENV['GH_TOKEN'])
set :joss_editor_team_id, 2009411

# Before we handle the request we extract the issue body to grab the whedon
# command (if present).
before do
  sleep(1000)
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
  when /assign (.*) as reviewer/i
    # TODO actually assign the reviewer
    respond "OK, the reviewer is #{$1}"
  when /assign (.*) as editor/i
    # TODO actually assign the editor
    respond "OK, the editor is #{$1}"
  when /start review magic-word=(.*)|start review/i
    respond "OK starting the review"
  when /list editors/i
    # TODO list editors
    respond editors.join('\n')
  when /list reviewers/i
    # TODO list the reviewers
    respond reviewers
  end
end

def respond(comment)
  settings.github.add_comment(@nwo, @issue_id, comment)
end

def reviewers
  "Here's the current list of JOSS reviewers: https://gist.github.com/arfon/5317c568cb32c7b917fea3c13958131d"
end

# Return an array of editor usernames for JOSS editor list
def editors
  settings.github.team_members(settings.joss_editor_team_id).collect { |e| "@#{e.login}" }
end
