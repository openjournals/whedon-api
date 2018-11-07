require_relative 'github'
require_relative 'workers'
require 'sinatra/base'
require 'fileutils'
require 'json'
require 'octokit'
require 'rest-client'
require 'sinatra/config_file'
require 'whedon'
require 'yaml'
require 'pry'

include GitHub

class WhedonApi < Sinatra::Base
  register Sinatra::ConfigFile

  set :views, Proc.new { File.join(root, "responses") }

  config_file "config/settings-#{ENV['RACK_ENV']}.yml"
  set :configs, {}
  set :initialized, false

  before do
    set_configs unless journal_configs_initialized?

    if %w[heartbeat].include? request.path_info.split('/')[1]
      pass
    else
      sleep(2) unless testing? # This seems to help with auto-updating GitHub issue threads
      params = JSON.parse(request.env["rack.input"].read)

      # Only work with issues. Halt if there isn't an issue in the JSON
      halt 422 if params['issue'].nil?

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

      halt 422 unless @config # We probably want to restrict this
    end
  end

  def journal_configs_initialized?
    settings.initialized
  end

  def testing?
    ENV['RACK_ENV'] == "test"
  end

  def set_configs
    # 'settings.journals' comes from sinatra/config_file
    settings.journals.each do |journal|
      journal.each do |nwo, params|
        team_id = params["editor_team_id"]
        params["editors"] = github_client.team_members(team_id).collect { |e| e.login }.sort
        settings.configs[nwo] = OpenStruct.new params
      end
    end

    settings.initialized = true
  end

  def say_hello
    if issue.title.match(/^\[REVIEW\]:/)
      reviewer = issue.body.match(/\*\*Reviewer:\*\*\s*(@\S*|Pending)/i)[1]
      respond erb :reviewer_welcome, :locals => { :reviewer => reviewer, :nwo => @nwo }
    # Newly created [PRE REVIEW] issue. Time to say hello
    elsif assignees.any?
      repo_detect
      respond erb :welcome, :locals => { :editor => assignees.first }
    else
      repo_detect
      respond erb :welcome, :locals => { :editor => nil }
    end
    process_pdf
  end

  # When an issue is closed we want to encourage authors to add the JOSS status
  # badge to their README but also potentially donate to JOSS (and sign up as a
  # future reviewer)
  def say_goodbye
    if review_issue?
      # If the REVIEW has been marked as 'accepted'
      if issue.labels.collect {|l| l.name }.include?('accepted')
        respond erb :goodbye, :locals => {:site_host => @config.site_host,
                                          :site_name => @config.site_name,
                                          :reviewers => @config.reviewers_signup,
                                          :doi_prefix => @config.doi_prefix,
                                          :doi_journal => @config.doi_journal,
                                          :issue_id => @issue_id,
                                          :donate_url => @config.donate_url}
      end
    end
  end

  def review_issue?
    issue.title.match(/^\[REVIEW\]:/)
  end

  def assignees
    @assignees ||= github_client.issue(@nwo, @issue_id).assignees.collect { |a| a.login }
  end

  def robawt_respond
    case @message
    when /\A@whedon commands/i
      if @config.editors.include?(@sender)
        respond erb :commands
      else
        respond erb :commands_public
      end
    when /\A@whedon assign (.*) as reviewer/i
      check_editor
      assign_reviewer($1)
      respond "OK, the reviewer is #{$1}"
    when /\A@whedon add (.*) as reviewer/i
      check_editor
      add_reviewer($1)
      respond "OK, #{$1} is now a reviewer"
    when /\A@whedon remove (.*) as reviewer/i
      check_editor
      remove_reviewer($1)
      respond "OK, #{$1} is no longer a reviewer"
    when /\A@whedon assign (.*) as editor/i
      check_editor
      assign_editor($1)
      respond "OK, the editor is #{$1}"
    when /\A@whedon set (.*) as archive/
      check_editor
      assign_archive($1)
    when /\A@whedon start review/i
      check_editor
      if editor && reviewers.any?
        review_issue_id = start_review
        respond erb :start_review, :locals => { :review_issue_id => review_issue_id, :nwo => @nwo }
      else
        respond erb :missing_editor_reviewer
        halt
      end
    when /\A@whedon list editors/i
      respond erb :editors, :locals => { :editors => @config.editors }
    when /\A@whedon list reviewers/i
      respond all_reviewers
    when /\A@whedon assignments/i
      reviewers, editors = assignments
      respond erb :assignments, :locals => { :reviewers => reviewers, :editors => editors, :all_editors => @config.editors }
    when /\A@whedon generate pdf from branch (.*)/
      process_pdf($1)
    when /\A@whedon generate pdf/i
      process_pdf
    when /\A@whedon accept deposit=true/i
      check_eic
      deposit(dry_run=false)
    when /\A@whedon accept/i
      check_editor
      deposit(dry_run=true)
    end
  end

  # How Whedon talks
  def respond(comment, nwo=nil, issue_id=nil)
    nwo ||= @nwo
    issue_id ||= @issue_id
    github_client.add_comment(nwo, issue_id, comment)
  end

  def archive_doi?
    archive = issue.body[/(?<=\*\*Archive:\*\*.<a\shref=)"(.*?)"/]
    if archive
      return true
    else
      return false
    end
  end

  def deposit(dry_run)
    if review_issue?
      # should check here that the archive DOI is set...

      if !archive_doi?
        respond "No archive DOI set. Exiting..."
        return
      end

      if dry_run == true
        respond "```\nAttempting dry run of processing paper acceptance...\n```"
        DepositWorker.perform_async(@config.papers,
                                    @config.site_host,
                                    @config.site_name,
                                    @nwo,
                                    @issue_id,
                                    @config.doi_journal,
                                    @config.journal_issn,
                                    @config.journal_launch_date,
                                    dry_run=true,
                                    nil, nil, nil)
      else
        label_issue(@nwo, @issue_id, ['accepted'])

        respond "```\nDoing it live! Attempting automated processing of paper acceptance...\n```"
        DepositWorker.perform_async(@config.papers,
                                    @config.site_host,
                                    @config.site_name,
                                    @nwo,
                                    @issue_id,
                                    @config.doi_journal,
                                    @config.journal_issn,
                                    @config.journal_launch_date,
                                    dry_run=false,
                                    @config.crossref_username,
                                    @config.crossref_password,
                                    @config.site_api_key)
      end
    else
      respond "I can't accept a paper that hasn't been reviewed!"
    end
  end

  # Download and compile the PDF
  def process_pdf(custom_branch=nil)
    # TODO refactor this so we're not passing so many arguments to the method
    if custom_branch
      respond "```\nAttempting PDF compilation from custom branch #{custom_branch}. Reticulating splines etc...\n```"
    else
      respond "```\nAttempting PDF compilation. Reticulating splines etc...\n```"
    end

    PDFWorker.perform_async(@config.to_h, custom_branch, @nwo, @issue_id)
  end

  # Detect the languages and license of the review repository
  def repo_detect
    RepoWorker.perform_async(@nwo, @issue_id, @config.journal_launch_date)
  end

  def assign_archive(doi_string)
    doi = doi_string[/\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'<>])\S)+)\b/]
    if doi
      doi_with_url = "<a href=\"https://doi.org/#{doi}\" target=\"_blank\">#{doi}</a>"
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
  def all_reviewers
    "Here's the current list of reviewers: #{@config.reviewers}"
  end

  # Change the editor on an issue. This is a two-step process:
  # 1. Change the review issue assignee
  # 2. Update the editor listed at the top of the issue

  # TODO: Refactor this mess
  def assign_editor(new_editor)
    puts "NEW EDITOR is #{new_editor}"
    new_editor = new_editor.gsub(/^\@/, "").strip
    new_body = issue.body.gsub(/\*\*Editor:\*\*\s*(@\S*|Pending)/i, "**Editor:** @#{new_editor}")
    # This line updates the GitHub issue with the new editor
    github_client.update_issue(@nwo, @issue_id, issue.title, new_body, :assignees => [])

    if @config.site_host == "http://joss.theoj.org"
      # Next update JOSS application to notify the editor has been changed
      # Currently we're only doing this for JOSS
      url = "#{@config.site_host}/papers/api_assign_editor?id=#{@issue_id}&editor=#{new_editor}&secret=#{@config.site_api_key}"
      response = RestClient.post(url, "")
    end

    reviewer_logins = reviewers.map { |reviewer_name| reviewer_name.sub(/^@/, "") }
    update_assignees([new_editor] | reviewer_logins)
  end

  # Change the reviewer listed at the top of the issue
  def assign_reviewer(new_reviewer)
    set_reviewers([new_reviewer])
  end

  def add_reviewer(reviewer)
    set_reviewers(reviewers + [reviewer])
  end

  def remove_reviewer(reviewer)
    set_reviewers(reviewers - [reviewer])
  end

  def set_reviewers(reviewer_list)
    reviewer_logins = reviewer_list.map { |reviewer_name| reviewer_name.sub(/^@/, "").downcase }.uniq
    label = reviewer_list.empty? ? "Pending" : reviewer_list.join(", ")
    new_body = issue.body.gsub(/\*\*Reviewers?:\*\*\s*(.+?)\r?\n/i, "**Reviewers:** #{label}\r\n")
    reviewer_logins.each do |reviewer_name|
      github_client.add_collaborator(@nwo, reviewer_name)
    end
    github_client.update_issue(@nwo, @issue_id, issue.title, new_body, :assignees => [])
    update_assignees([editor] | reviewer_logins)
  end

  def editor
    issue.body.match(/\*\*Editor:\*\*\s*.@(\S*)/)[1]
  end

  def reviewers
    issue.body.match(/Reviewers?:\*\*\s*(.+?)\r?\n/)[1].split(", ") - ["Pending"]
  end

  def update_assignees(logins)
    data = { "assignees" => logins }
    url = "https://api.github.com/repos/#{@nwo}/issues/#{@issue_id}/assignees?access_token=#{ENV['GH_TOKEN']}"
    RestClient.post(url, data.to_json)
  end

  def start_review
    # Check we have an editor and a reviewer
    if review_issue? # Don't start a review if it has already started
      respond "Can't start a review when the review has already started"
      halt 422
    end

    if reviewers.empty?
      respond "Can't start a review without reviewers"
      halt 422
    end

    if !editor
      respond "Can't start a review without an editor"
      halt 422
    end

    reviewer_logins = reviewers.map { |reviewer_name| reviewer_name.sub(/^@/, "") }
    url = "#{@config.site_host}/papers/api_start_review?id=#{@issue_id}&editor=#{editor}&reviewers=#{reviewer_logins.join(',')}&secret=#{@config.site_api_key}"
    # TODO let's do some error handling here please
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

  # Check that the person sending the command is an editor-in-chief
  def check_eic
    unless @config.eics.include?(@sender)
      respond "I'm sorry @#{@sender}, I'm afraid I can't do that. That's something only editor-in-chiefs are allowed to do."
      halt 403
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
end
