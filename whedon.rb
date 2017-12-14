require_relative 'github'
require 'fileutils'
require 'json'
require 'octokit'
require 'rest-client'
require 'sidekiq'
require 'sinatra'
require 'sinatra/config_file'
require 'whedon'
require 'yaml'


include GitHub

set :views, Proc.new { File.join(root, "responses") }
set :magic_word, "bananas"

config_file 'config/settings.yml'
set :configs, {}

# 'settings.journals' comes from sinatra/config_file
settings.journals.each do |journal|
  journal.each do |nwo, params|
    team_id = params["editor_team_id"]
    params["editors"] = github_client.team_members(team_id).collect { |e| e.login }.sort
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

    if @action == 'opened' || @action == 'closed'
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

  if @action == "closed"
    say_goodbye
    halt
  end

  robawt_respond if @message
end

# When an issue is first opened we want to do a few things:
# - If this is the main REVIEW issue then we want to respond with the welcome
#   message and also try and compile the paper
# - If this is a PRE-REVIEW issue then we want to respond with the welcome
#   message but we also want to detect the programming languages of the project
#   to help with editor and reviewer assignments
def say_hello
  if issue.title.match(/^\[REVIEW\]:/)
    reviewer = issue.body.match(/\*\*Reviewer:\*\*\s*(@\S*|Pending)/i)[1]
    respond erb :reviewer_welcome, :locals => { :reviewer => reviewer, :nwo => @nwo }
  # Newly created [PRE REVIEW] issue. Time to say hello
  elsif assignees.any?
    detect_languages
    respond erb :welcome, :locals => { :editor => assignees.first }
  else
    detect_languages
    respond erb :welcome, :locals => { :editor => nil }
  end
  process_pdf
end

# When an issue is closed we want to encourage authors to add the JOSS status
# badge to their README but also potentially donate to JOSS (and sign up as a
# future reviewer)
def say_goodbye
  if issue.title.match(/^\[REVIEW\]:/)
    # If the REVIEW has been marked as 'accepted'
    if issue.labels.collect {|l| l.name }.include?('accepted')
      respond erb :goodbye, :locals => {:site_host => @config.site_host,
                                        :site_name => @config.site_name,
                                        :reviewers => @config.reviewers,
                                        :doi_prefix => @config.doi_prefix,
                                        :doi_journal => @config.doi_journal,
                                        :issue_id => @issue_id}
    end
  end
end

def assignees
  @assignees ||= github_client.issue(@nwo, @issue_id).assignees.collect { |a| a.login }
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
    process_pdf
  end
end

# How Whedon talks
def respond(comment, nwo=nil, issue_id=nil)
  nwo ||= @nwo
  issue_id ||= @issue_id
  github_client.add_comment(nwo, issue_id, comment)
end

# Download and compile the PDF
def process_pdf
  puts "In #process_pdf"
  # TODO refactor this so we're not passing so many arguments to the method
  respond "```\nAttempting PDF compilation. Reticulating splines etc...\n```"
  PDFWorker.new.perform(@config.papers, @config.site_host, @config.site_name, @nwo, @issue_id, @config.doi_journal)
end

# Detect the languages of the review repository
def detect_languages
  puts "In #process_pdf"
  LanguageWorker.perform_async(@nwo, @issue_id)
end

def assign_archive(doi_string)
  doi = doi_string[/\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'<>])\S)+)\b/]
  if doi
    doi_with_url = "<a href=\"http://dx.doi.org/#{doi}\" target=\"_blank\">#{doi}</a>"
    new_body = issue.body.gsub(/\*\*Archive:\*\*\s*(.*|Pending)/i, "**Archive:** #{doi_with_url}")
    github_client.update_issue(@nwo, @issue_id, issue.title, new_body)
    respond "OK. #{doi_with_url} is the archive."
  else
    respond "#{doi_string} doesn't look like an archive DOI."
  end
end

def assignments
  issues = github_client.list_issues(@nwo, :state => 'open')
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
  github_client.update_issue(@nwo, @issue_id, issue.title, new_body, :assignees => [])
  update_assigness([new_editor])
end

# Change the reviewer listed at the top of the issue
def assign_reviewer(new_reviewer)
  new_reviewer = new_reviewer.gsub(/^\@/, "")
  editor = issue.body.match(/\*\*Editor:\*\*\s*.@(\S*)/)[1]
  new_body = issue.body.gsub(/\*\*Reviewer:\*\*\s*(@\S*|Pending)/i, "**Reviewer:** @#{new_reviewer}")
  github_client.add_collaborator(@nwo, new_reviewer)
  puts "NWO: #{@nwo}"
  puts "ISSUE ID: #{@issue_id}"
  puts "TITLE: #{issue.title}"
  puts "BODY: #{new_body}"
  puts "ASSIGNEES #{[new_reviewer, editor]}"
  github_client.update_issue(@nwo, @issue_id, issue.title, new_body, :assignees => [])
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
  url = "#{@config.site_host}/papers/api_start_review?id=#{@issue_id}&editor=#{editor}&reviewer=#{reviewer}&secret=#{@config.site_api_key}"
  # TODO let's do some error handling here please
  puts "POSTING TO #{url}"
  response = RestClient.post(url, "")
  paper = JSON.parse(response)
  return paper['review_issue_id']
end

def issue
  @issue ||= github_client.issue(@nwo, @issue_id)
end

# Check that the person sending the command is an editor
def check_editor
  unless @config.editors.include?(@sender)
    respond "I'm sorry @#{@sender}, I'm afraid I can't do that. That's something only editors are allowed to do."
    halt 403
  end
end

########################
#  Background workers  #
########################

# This worker runs Linguist (https://github.com/github/linguist) on the software
# being reviewed and adds labels to the PRE-REVIEW issue for the top three
# detected languages
class LanguageWorker
  require 'rugged'
  require 'linguist'

  include Sidekiq::Worker

  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(nwo, issue_id)
    set_env(nwo)

    # Download the paper
    stdout, stderr, status = download(issue_id)

    if status.success?
      languages = detect_languages(issue_id)
      label_issue(nwo, issue_id, languages) if languages.any?
    else
      bg_respond(nwo, issue_id, "Downloading of the repository for issue ##{issue_id} failed with the following error: \n\n #{stderr}") and return
    end
  end

  def label_issue(nwo, issue_id, languages)
    github_client.add_labels_to_an_issue(nwo, issue_id, languages)
  end

  def detect_languages(issue_id)
    repo = Rugged::Repository.new("tmp/#{issue_id}")
    project = Linguist::Repository.new(repo, repo.head.target_id)

    # Take top three languages from Linguist
    project.languages.keys.take(3)
  end

  def download(issue_id)
    puts "Downloading #{ENV['REVIEW_REPOSITORY']}"
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
  end

  # The Whedon gem expects a bunch of environment variables to be available
  # and this method sets them.
  def set_env(nwo)
    ENV['REVIEW_REPOSITORY'] = nwo
  end
end

# This is the Sidekiq worked that processes PDFs. It leverages the Whedon gem to
# carry out the majority of its actions. Where possible, we try and capture
# errors from any of the executed tasks and report them back to the review issue
class PDFWorker
  require 'open3'

  include Sidekiq::Worker

  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(papers_repo, site_host, site_name, nwo, issue_id, journal_alias)
    set_env(papers_repo, site_host, site_name, nwo)

    # Download the paper
    stdout, stderr, status = download(issue_id)

    if !status.success?
      bg_respond(nwo, issue_id, "Downloading of the repository for issue ##{issue_id} failed with the following error: \n\n #{stderr}") and return
    end

    # Compile the paper
    pdf_path, stderr, status = compile(issue_id)

    if !status.success?
      bg_respond(nwo, issue_id, "PDF failed to compile for issue ##{issue_id} with the following error: \n\n #{stderr}") and return
    end

    puts "WHAT IS IN THIS DIRECTORY?!"
    puts `ls tmp/59/paper/`

    # If we've got this far then push a copy of the PDF to the papers repository
    puts "Creating Git branch"
    create_or_update_git_branch(issue_id, papers_repo, journal_alias)

    puts "Uploading #{pdf_path}"
    pdf_url = create_git_pdf(pdf_path, issue_id, papers_repo, journal_alias)

    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pdf_url)
  end

  # Use the Whedon gem to download the software to a local tmp directory
  def download(issue_id)
    puts "Downloading #{ENV['REVIEW_REPOSITORY']}"
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
  end

  # Use the Whedon gem to compile the paper
  def compile(issue_id)
    puts "Compiling #{ENV['REVIEW_REPOSITORY']}/#{issue_id}"
    Open3.capture3("whedon prepare #{issue_id}")
  end

  # This method allows the background worker to post messages to GitHub.
  def bg_respond(nwo, issue_id, comment)
    github_client.add_comment(nwo, issue_id, "```\n#{comment}\n```")
  end

  # GitHub stuff (to be refactored!)
  def get_master_ref(papers)
    github_client.refs(papers).select { |r| r[:ref] == "refs/heads/master" }.first.object.sha
  end

  # Create or update branch on GitHub in the papers repository
  # If the branch already exists, delete the paper that's already in the branch.
  # If the branch doesn't exist, create it.
  def create_or_update_git_branch(issue_id, papers_repo, journal_alias)
    id = "%05d" % issue_id
    pdf_path = "#{journal_alias}.#{id}/10.21105.#{journal_alias}.#{id}.pdf"

    begin
      ref_sha = github_client.refs(papers_repo, "heads/#{journal_alias}.#{id}").object.sha
      blob_sha = github_client.commit(papers_repo, ref_sha).files.first.sha
      github_client.delete_contents(papers_repo,
                                    pdf_path,
                                    "Deleting 10.21105.#{journal_alias}.#{id}.pdf",
                                    blob_sha,
                                    :branch => "#{journal_alias}.#{id}")
    rescue Octokit::NotFound
      github_client.create_ref(papers_repo, "heads/#{journal_alias}.#{id}", get_master_ref(papers_repo))
    end
  end

  # Use the GitHub Contents API (https://developer.github.com/v3/repos/contents/)
  # to write the compiled PDF to a named branch.
  # Returns the URL to the PDF on GitHub
  def create_git_pdf(file_path, issue_id, papers_repo, journal_alias)
    id = "%05d" % issue_id
    pdf_path = "#{journal_alias}.#{id}/10.21105.#{journal_alias}.#{id}.pdf"

    gh_response = github_client.create_contents(papers_repo,
                                                pdf_path,
                                                "Creating 10.21105.#{journal_alias}.#{id}.pdf",
                                                File.open("#{file_path.strip}").read,
                                                :branch => "#{journal_alias}.#{id}")

    return gh_response.content.html_url
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
