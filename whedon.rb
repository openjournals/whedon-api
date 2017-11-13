require 'yaml'
require 'json'
require 'octokit'
require 'rest-client'
require 'sidekiq'
require 'sinatra'
require 'whedon'

set :views, Proc.new { File.join(root, "responses") }
set :gh_token, ENV["GH_TOKEN"]
set :github, Octokit::Client.new(:access_token => ENV["GH_TOKEN"])
set :magic_word, "bananas"

set :configs, {}
YAML.load_file("config/settings.yml").each do |nwo, config|
  team_id = config["editor_team_id"]
  config["editors"] = settings.github.team_members(team_id).collect { |e| e.login }.sort
  settings.configs[nwo] = OpenStruct.new config
end

# Sidekiq configuration
Sidekiq.configure_server do |config|
  config.redis = { :url => ENV["REDISTOGO_URL"] }
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
  when /\A@whedon generate pdf/i
    puts "Attempting to compile PDF"
    respond "```\n#{process_pdf}```"
  end
end

# How Whedon talks
def respond(comment, nwo=nil, issue_id=nil)
  nwo ||= @nwo
  issue_id ||= @issue_id
  settings.github.add_comment(nwo, issue_id, comment)
end

# Download and compile the PDF
def process_pdf
  puts "In #process_pdf"
  # TODO refactor this so we're not passing so many arguments to the method

  pdf_path = WhedonWorker.new.perform(@config.papers, @config.site_host, @config.site_name, @nwo, @issue_id)

  puts "Creating Git branch"
  create_or_update_git_branch

  puts "Uploading #{pdf_path}"

  puts `ls tmp/49/paper`
  create_git_pdf(pdf_path)
  # WhedonWorker.perform_async(@config.papers, @config.site_host, @config.site_name, @nwo, @issue_id)
end

# GitHub stuff (to be refactored!)

def get_master_ref
  settings.github.refs("openjournals/joss-papers-testing").select { |r| r[:ref] == "refs/heads/master" }.first.object.sha
end

# Create or update branch
def create_or_update_git_branch
  id = "%05d" % @issue_id

  begin
    # If the PDF is there already then delete it
    settings.github.contents('openjournals/joss-papers-testing', :path => "10.21105.joss.#{id}.pdf", :ref => "heads/joss.#{id}")
    blob_sha = settings.github.contents("openjournals/joss-reviews-testing", :path => "10.21105.joss.#{id}.pdf", :ref => "heads/joss.#{id}").sha
    settings.github.delete_contents("openjournals/joss-reviews-testing",
                                    "10.21105.joss.#{id}.pdf",
                                    "Deleting 10.21105.joss.#{id}.pdf",
                                    blob_sha,
                                    :branch => "joss.#{id}")
  rescue Octokit::NotFound
    settings.github.create_ref("openjournals/joss-papers-testing", "heads/joss.#{id}", get_master_ref)
  end
end

def create_git_pdf(file_path)
  id = "%05d" % @issue_id

  puts "CURRENT DIRECTORY"
  puts Dir.pwd
  settings.github.create_contents("openjournals/joss-reviews-testing",
                                  "10.21105.joss.#{id}.pdf",
                                  "Creating 10.21105.joss.#{id}.pdf",
                                  File.open("#{file_path.strip}").read,
                                  :branch => "joss.#{id}")
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

class WhedonWorker
  include Sidekiq::Worker

  def perform(papers, site_host, site_name, nwo, issue_id)
    bg_respond("Hello from the background worker", nwo, issue_id)
    set_env(papers, site_host, site_name, nwo)
    download(issue_id)
    compile(issue_id)
  end

  def download(issue_id)
    puts "Downloading #{ENV['REVIEW_REPOSITORY']}"
    `whedon download #{issue_id}`
  end

  def compile(issue_id)
    puts "Compiling #{ENV['REVIEW_REPOSITORY']}/#{issue_id}"
    `whedon prepare #{issue_id}`
  end

  def bg_respond(one, two, three)
    puts ENV
  end

  # The Whedon gem expects a bunch of environment variables to be available
  # and this method sets them.
  def set_env(papers, site_host, site_name, nwo)
    ENV['REVIEW_REPOSITORY'] = nwo
    ENV['DOI_PREFIX'] = "10.21105"
    ENV['PAPER_REPOSITORY'] = papers
    ENV['JOURNAL_URL'] = site_host
    ENV['JOURNAL_NAME'] = site_name
  end
end
