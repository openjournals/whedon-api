require 'json'
require 'octokit'
require 'rest-client'
require 'sinatra'

set :views, Proc.new { File.join(root, "responses") }
set :github, Octokit::Client.new(:access_token => ENV['GH_TOKEN'])
set :joss_api_key, ENV['JOSS_API_KEY']
set :joss_editor_team_id, 2009411
set :magic_word, "bananas"
set :editors, ['acabunoc', 'arfon', 'cMadan', 'danielskatz', 'jakevdp', 'karthik',
               'katyhuff', 'Kevin-Mattheus-Moerman', 'kyleniemeyer', 'labarba',
               'mgymrek', 'pjotrp', 'tracykteal']

# Before we handle the request we extract the issue body to grab the whedon
# command (if present).
before do
  sleep(2) # This seems to help with auto-updating GitHub issue threads
  params = JSON.parse(request.env["rack.input"].read)

  # Only work with issues. Halt if there isn't an issue in the JSON
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
    assign_reviewer($1)
    respond "OK, the reviewer is #{$1}"
  when /\A@whedon assign (.*) as editor/i
    check_editor
    assign_editor($1)
    respond "OK, the editor is #{$1}"
  when /\A@whedon set (.*) as archive/
    check_editor
    assign_archive($1)
  when /\A@whedon start review magic-word=(.*)|\A@whedon start review/i
    check_editor
    # TODO actually post something to the API
    word = $1
    if word && word == settings.magic_word
      review_issue_id = start_review
      respond erb, :locals => { :review_issue_id => review_issue_id }
    else
      respond erb :magic_word, :locals => { :magic_word => settings.magic_word }
      halt
    end
  when /\A@whedon list editors/i
    respond erb :editors, :locals => { :editors => editors }
  when /\A@whedon list reviewers/i
    respond reviewers
  end
end

# How Whedon talks
def respond(comment)
  settings.github.add_comment(@nwo, @issue_id, comment)
end

def assign_archive(doi_string)
  doi = doi_string[/\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'<>])\S)+)\b/]
  if doi
    doi_with_url = "<a href='http://dx.doi.org/#{doi}' target='_blank'>#{doi}</a>"
    new_body = issue.body.gsub(/\*\*Archive:\*\*\s*(.*|Pending)/i, "**Archive:** #{doi_with_url}")
    settings.github.update_issue(@nwo, @issue_id, issue.title, new_body)
    respond "OK. #{doi_with_url} is the archive."
  else
    respond "#{doi_string} doesn't look like an archive DOI."
  end
end

# Returns a string response with URL to Gist of reviewers
def reviewers
  "Here's the current list of JOSS reviewers: https://gist.github.com/arfon/5317c568cb32c7b917fea3c13958131d"
end

# Return an array of editor usernames for JOSS editor list
def editors
  @editors ||= settings.github.team_members(settings.joss_editor_team_id).collect { |e| e.login }
end

# Change the editor on an issue. This is a two-step process:
# 1. Change the review issue assignee
# 2. Update the editor listed at the top of the issue
def assign_editor(new_editor)
  new_editor = new_editor.gsub(/^\@/, "")
  new_body = issue.body.gsub(/\*\*Editor:\*\*\s*(@\S*|Pending)/i, "**Editor:** @#{new_editor}")
  settings.github.update_issue(@nwo, @issue_id, issue.title, new_body, :assignees => [])
  update_assigness([new_editor])
end

# Change the reviewer listed at the top of the issue
def assign_reviewer(new_reviewer)
  new_reviewer = new_reviewer.gsub(/^\@/, "")
  editor = issue.body.match(/\*\*Editor:\*\*\s*.@(\S*)/)[1]
  new_body = issue.body.gsub(/\*\*Reviewer:\*\*\s*(@\S*|Pending)/i, "**Reviewer:** @#{new_reviewer}")
  settings.github.add_collaborator(@nwo, new_reviewer)
  puts "NWO: #{@nwo}"
  puts "ISSUE ID: #{@issue_id}"
  puts "TITLE: #{issue.title}"
  puts "BODY: #{new_body}"
  puts "ASSIGNEES #{[new_reviewer, editor]}"
  settings.github.update_issue(@nwo, @issue_id, issue.title, new_body, :assignees => [])
  update_assigness([new_reviewer, editor])
end

def update_assigness(assignees)
  data = { "assignees" => assignees }
  url = "https://api.github.com/repos/#{@nwo}/issues/#{@issue_id}/assignees?access_token=#{ENV['GH_TOKEN']}"
  RestClient.post(url, data.to_json)
end

def start_review
  editor = issue.body.match(/\*\*Editor:\*\*\s*.@(\S*)/)[1]
  reviewer = issue.body.match(/\*\*Reviewer:\*\*\s*.@(\S*)/)[1]
  # Check we have an editor and a reviewer
  raise unless (editor && reviewer)
  url = "http://joss.theoj.org/papers/api_start_review?id=#{@issue_id}&editor=#{editor}&reviewer=#{reviewer}&secret=#{settings.joss_api_key}"
  # TODO let's do some error handling here please
  puts "POSTING TO #{url}"
  response = RestClient.post(url, "")
  paper = JSON.parse(response)
  return paper['review_issue_id']
end

def issue
  @issue ||= settings.github.issue(@nwo, @issue_id)
end

# Check that the person sending the command is an editor
def check_editor
  unless settings.editors.include?(@sender)
    respond "I'm sorry @#{@sender}, I'm afraid I can't do that. That's something only JOSS editors are allowed to do."
    halt 403
  end
end
