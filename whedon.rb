require 'yaml'
require 'json'
require 'octokit'
require 'rest-client'
require 'sinatra'
require 'sinatra/config_file'

set :views, Proc.new { File.join(root, "responses") }
set :gh_token, ENV["GH_TOKEN"]
set :github, Octokit::Client.new(:access_token => settings.gh_token)
set :magic_word, "bananas"

config_file 'config/settings.yml'
set :configs, {}

# 'settings.journals' comes from sinatra/config_file
settings.journals.each do |journal|
  journal.each do |nwo, params|
    team_id = params["editor_team_id"]
    params["editors"] = settings.github.team_members(team_id).collect { |e| e.login }.sort
    settings.configs[nwo] = OpenStruct.new params
  end
end

# Before we handle the request we extract the issue body to grab the whedon
# command (if present).
before do
  if %w[heartbeat].include? request.path_info.split('/')[1]
    pass
  else
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
    @config = settings.configs[@nwo]
    halt unless @config # We probably want to restrict this
  end
end

get '/heartbeat' do
  "BOOM boom. BOOM boom. BOOM boom."
end

post '/dispatch' do
  if @action == "opened"
    say_hello
    halt
  end

  robawt_respond if @message
end

def say_hello
  if issue.title.match(/^\[REVIEW\]:/)
    reviewer = issue.body.match(/\*\*Reviewer:\*\*\s*(@\S*|Pending)/i)[1]
    respond erb :reviewer_welcome, :locals => { :reviewer => reviewer, :nwo => @nwo }
  # Newly created [PRE REVIEW] issue. Time to say hello
  elsif assignees.any?
    respond erb :welcome, :locals => { :editor => assignees.first }
  else
    respond erb :welcome, :locals => { :editor => nil }
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
      respond erb :start_review, :locals => { :review_issue_id => review_issue_id, :nwo => @nwo }
    else
      respond erb :magic_word, :locals => { :magic_word => settings.magic_word }
      halt
    end
  when /\A@whedon list editors/i
    respond erb :editors, :locals => { :editors => @config.editors }
  when /\A@whedon list reviewers/i
    respond reviewers
  when /\A@whedon assignments/i
    reviewers, editors = assignments
    respond erb :assignments, :locals => { :reviewers => reviewers, :editors => editors, :all_editors => @config.editors }
  end
end

# How Whedon talks
def respond(comment)
  settings.github.add_comment(@nwo, @issue_id, comment)
end

def assign_archive(doi_string)
  doi = doi_string[/\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'<>])\S)+)\b/]
  if doi
    doi_with_url = "<a href=\"http://dx.doi.org/#{doi}\" target=\"_blank\">#{doi}</a>"
    new_body = issue.body.gsub(/\*\*Archive:\*\*\s*(.*|Pending)/i, "**Archive:** #{doi_with_url}")
    settings.github.update_issue(@nwo, @issue_id, issue.title, new_body)
    respond "OK. #{doi_with_url} is the archive."
  else
    respond "#{doi_string} doesn't look like an archive DOI."
  end
end

def assignments
  issues = settings.github.list_issues(@nwo, :state => 'open')
  editors = Hash.new(0)
  reviewers = Hash.new(0)

  issues.each do |issue|
    if issue.body.match(/\*\*Editor:\*\*\s*(@\S*|Pending)/i)
      editor = issue.body.match(/\*\*Editor:\*\*\s*(@\S*|Pending)/i)[1]
      editors[editor] += 1
    end

    if issue.body.match(/\*\*Reviewer:\*\*\s*(@\S*|Pending)/i)
      reviewer = issue.body.match(/\*\*Reviewer:\*\*\s*(@\S*|Pending)/i)[1]
      reviewers[reviewer] += 1
    end
  end

  sorted_editors = editors.sort_by {|_, value| value}.to_h
  sorted_reviewers = reviewers.sort_by {|_, value| value}.to_h

  return sorted_reviewers, sorted_editors
end

# Returns a string response with URL to Gist of reviewers
def reviewers
  "Here's the current list of reviewers: #{@config.reviewers}"
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
  url = "https://api.github.com/repos/#{@nwo}/issues/#{@issue_id}/assignees?access_token=#{settings.gh_token}"
  RestClient.post(url, data.to_json)
end

def start_review
  editor = issue.body.match(/\*\*Editor:\*\*\s*.@(\S*)/)[1]
  reviewer = issue.body.match(/\*\*Reviewer:\*\*\s*.@(\S*)/)[1]
  # Check we have an editor and a reviewer
  raise unless (editor && reviewer)
  url = "#{@config.site_host}/papers/api_start_review?id=#{@issue_id}&editor=#{editor}&reviewer=#{reviewer}&secret=#{@config.site_api_key}"
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
  unless @config.editors.include?(@sender)
    respond "I'm sorry @#{@sender}, I'm afraid I can't do that. That's something only editors are allowed to do."
    halt 403
  end
end
