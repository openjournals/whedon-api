require 'json'
require 'octokit'
require 'sinatra'

set :views, Proc.new { File.join(root, "responses") }
set :github, Octokit::Client.new(:access_token => ENV['GH_TOKEN'])
set :joss_editor_team_id, 2009411
set :magic_word, "bananas"
set :editors, ['acabunoc', 'cMadan', 'danielskatz', 'jakevdp', 'karthik',
               'katyhuff', 'kyleniemeyer', 'labarba', 'mgymrek', 'pjotrp', 'tracykteal']

# Before we handle the request we extract the issue body to grab the whedon
# command (if present).
before do
  sleep(1)
  params = JSON.parse(request.env["rack.input"].read)
  # Only work with issues. Halt if there isn't an issue in the JSON
  puts "PARAMS: #{params}"
  halt if params['issue'].nil?
  @action = params['action']
  @payload = params

  if @action == 'opened'
    @message = params['issue']['body']
  elsif @action == 'created'
    @message = params['comment']['body']
  end

  @sender = params['sender']['login']
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
  if assignees.any?
    respond erb :welcome, :locals => { :editor => assignees.first }
  else
    respond erb :welcome
  end
end

def assignees
  @assignees ||= settings.github.issue(@nwo, @issue_id).assignees.collect { |a| a.login }
end

def robawt_respond
  puts "ACTION: #{@action}"
  puts "MESSAGE: #{@message}"
  case @message
  when /\A@whedon commands/i
    respond erb :commands
  when /\A@whedon assign (.*) as reviewer/i
    check_editor
    # TODO actually assign the reviewer

    respond "OK, the reviewer is #{$1}"
  when /\A@whedon assign (.*) as editor/i
    check_editor
    # TODO actually assign the editor
    respond "OK, the editor is #{$1}"
  when /\A@whedon start review magic-word=(.*)|\Astart review/i
    check_editor
    respond "OK starting the review"
  when /\A@whedon list editors/i
    # TODO list editors
    respond erb :editors, :locals => { :editors => editors }
  when /\A@whedon list reviewers/i
    # TODO list the reviewers
    respond reviewers
  end
end

# How Whedon talks
def respond(comment)
  settings.github.add_comment(@nwo, @issue_id, comment)
end

# Returns a string response with URL to Gist of reviewers
def reviewers
  "Here's the current list of JOSS reviewers: https://gist.github.com/arfon/5317c568cb32c7b917fea3c13958131d"
end

# Return an array of editor usernames for JOSS editor list
def editors
  @editors ||= settings.github.team_members(settings.joss_editor_team_id).collect { |e| e.login }
end

# Check that the person sending the command is an editor
def check_editor
  unless settings.editors.include?(@sender)
    respond "I'm sorry @#{@sender}, I'm afraid I can't do that. That's something only JOSS editors are allowed to do."
    halt 403
  end
end
