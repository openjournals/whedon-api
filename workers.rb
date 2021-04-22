class PaperPreviewWorker
  require 'cloudinary'
  require 'sidekiq'
  require 'sidekiq_status'
  require 'whedon'

  include Sidekiq::Worker
  include SidekiqStatus::Worker

  sidekiq_options retry: false

  SidekiqStatus::Container.ttl = 600

  def perform(repository_address, journal, custom_branch=nil, sha)
     ENV["JOURNAL_LAUNCH_DATE"] = '2020-05-05'

    if custom_branch
      result, stderr, status = Open3.capture3("cd tmp && git clone --single-branch --branch #{custom_branch} #{repository_address} #{sha}")
    else
      result, stderr, status = Open3.capture3("cd tmp && git clone #{repository_address} #{sha}")
    end

    if !status.success?
      return result, stderr, status
    end

    paper_paths = find_paper_paths("tmp/#{sha}")

    journal = "joss"
    journal_name = "Journal of Open Source Software"

    if paper_paths.empty?
      self.payload = "Can't find any papers to compile. Make sure there's a file named <code>paper.md</code> in your repository."
      abort("Can't find any papers to compile.")
    elsif paper_paths.size == 1
      begin
        Whedon::Paper.new(sha, paper_paths.first)
      rescue RuntimeError => e
        self.payload = e.message
        abort("Can't find any papers to compile.")
        return
      end

      latex_template_path = "#{Whedon.resources}/#{journal}/latex.template"
      csl_file = "#{Whedon.resources}/#{journal}/apa.csl"
      directory = File.dirname(paper_paths.first)
      # TODO: may eventually want to swap out the latex template

      result, stderr, status = Open3.capture3("cd #{directory} && pandoc -V repository='#{repository_address}' -V archive_doi='PENDING' -V paper_url='PENDING' -V journal_name='#{journal_name}' -V formatted_doi='10.21105/#{journal}.0XXXX' -V review_issue_url='XXXX' -V graphics='true' -V issue='X' -V volume='X' -V page='X' -V logo_path='#{Whedon.resources}/#{journal}/logo.png' -V aas_logo_path='#{Whedon.resources}/#{journal}/aas-logo.png' -V year='XXXX' -V submitted='01 January XXXX' -V published='01 January XXXX' -V editor_name='Editor Name' -V editor_url='http://example.com' -V citation_author='Mickey Mouse et al.' -o #{sha}.pdf -V geometry:margin=1in --pdf-engine=xelatex --filter pandoc-citeproc #{File.basename(paper_paths.first)} --from markdown+autolink_bare_uris --csl=#{csl_file} --template #{latex_template_path}")

      if status.success?
        if File.exists?("#{directory}/#{sha}.pdf")
          response = Cloudinary::Uploader.upload("#{directory}/#{sha}.pdf")
          self.payload = response['url']
        end
      else
        self.payload = "Looks like we failed to compile the PDF with the following error: \n\n #{stderr}"
        abort("Looks like we failed to compile the PDF.")
      end
    else
      self.payload = "There seems to be more than one paper.md present. Aborting..."
      abort("There seems to be more than one paper.md present. Aborting...")
    end
  end

  def find_paper_paths(search_path=nil)
    search_path ||= "tmp/#{review_issue_id}"
    paper_paths = []

    Find.find(search_path) do |path|
      paper_paths << path if path =~ /\bpaper\.tex$|\bpaper\.md$/
    end

    return paper_paths
  end
end

class JBPreviewWorker
  require 'pathname'
  require 'sidekiq'
  require 'sidekiq_status'
  require 'whedon'

  include Sidekiq::Worker
  include SidekiqStatus::Worker

  sidekiq_options retry: false

  SidekiqStatus::Container.ttl = 600

  def perform(repository_address, journal, custom_branch=nil, sha)
    if custom_branch
      result, stderr, status = Open3.capture3("cd tmp && git clone --single-branch --branch #{custom_branch} #{repository_address} #{sha}")
    else
      result, stderr, status = Open3.capture3("cd tmp && git clone #{repository_address} #{sha}")
    end

    if !status.success?
      return result, stderr, status
    end

    jb_paths = find_jb("tmp/#{sha}")

    if jb_paths.empty?
      self.payload = "Can't find a Jupyter Book to build. Make sure there's a file named <code>_toc.yml</code> in your repository."
      abort("Can't find a Jupyter Book to build.")
    elsif jb_paths.size == 1
      begin
        original_path = Pathname(jb_paths.first)
        target_path = original_path.parent.parent
        result, stderr, status = Open3.capture3("pip install -r #{target_path}/requirements.txt && jupyter-book build #{target_path}/content/")
      rescue RuntimeError => e
        self.payload = e.message
        abort("Can't find a Jupyter Book to build.")
        return
      end

      directory = File.dirname(jb_paths.first)

      if status.success?
        if File.exists?("#{directory}/#{sha}/_build/html/index.html")
          self.payload = "https://www.ismercuryinretrograde.com/"
        end
      else
        self.payload = "Looks like we failed to build the Jupyter Book with the following error: \n\n #{stderr}"
        abort("Looks like we failed to build the Jupyter Book.")
      end
    else
      self.payload = "There seems to be more than one _toc.yml present. Aborting..."
      abort("There seems to be more than one _toc.yml present. Aborting...")
    end
  end

  def find_jb(search_path=nil)
    search_path ||= "tmp/#{review_issue_id}"
    jb_paths = []

    Find.find(search_path) do |path|
      jb_paths << path if path =~ /_toc\.yml/
    end

    return jb_paths
  end
end

class NLPreviewWorker
  require 'rest-client'
  require 'sidekiq'
  require 'sidekiq_status'
  require 'json'
  require 'uri'
  require_relative 'github'

  include Sidekiq::Worker
  include SidekiqStatus::Worker
  include GitHub

  sidekiq_options retry: false

  def perform(repository_address, journal, custom_branch=nil, sha)

  uri = URI(repository_address)
  gh_repo = uri.path[1...] # user/repo

  if custom_branch
    # Get latest sha with --book-build in comments in custom_branch
    latest_sha = get_latest_book_build_sha(gh_repo,custom_branch)
  else
    # Get latest sha with --book-build in comments 
    latest_sha = get_latest_book_build_sha(gh_repo)
  end

  if latest_sha.nil? 
    # Terminate 
    fail "Repository does not contain any commits with --build-book message."
  else
    post_params = {
      :repo_url => repository_address,
      :commit_hash => latest_sha
    }.to_json
  end

    response = RestClient::Request.new(
          method: :post,
          :url => 'http://neurolibre-data.conp.cloud:8081/api/v1/resources/books',
          verify_ssl: false,
          :user => 'neurolibre',
          :password => ENV['NEUROLIBRE_TESTAPI_TOKEN'],
          :payload => post_params,
          :headers => { :content_type => :json }
       ).execute do |response, request, result|
        case response.code
        when 409 # Conflict: Means that a build with requested hash already exists. 
          # In that case, first we'll attempt to return build book. 
          self.payload = response.to_str
          self.another_response = "See if it works"
          
        when 200
          [ :success, parse_json(response.to_str) ]
        else
          fail "Invalid response #{response.to_str} received."
        end
      end

      #data = { "repo_url" => repository_address }
      #url = "http://neurolibre-data.conp.cloud:8081/api/v1/resources/books"
      #response = RestClient.post(url, data.to_json, {:user => "neurolibre",:password => "#{ENV['NEUROLIBRE_TESTAPI_TOKEN']}"})
      #puts JSON.parse(response.to_str)
      #self.payload = JSON.parse(response)
  end

end

class ReviewReminderWorker
  require_relative 'github'
  require_relative 'config_helper'
  require 'sidekiq'

  include Sidekiq::Worker

  # Sets the Whedon environment
  include ConfigHelper
  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  # Need to respond with different message if author (not a reviewer)
  def perform(human, nwo, issue_id, config)
    # Make sure we're working with GitHub handles with '@' at the start
    unless human.start_with?('@')
      human = "@#{human}"
    end

    issue = github_client.issue(nwo, issue_id)
    return false if issue.state == 'closed'
    author = issue.body.match(/\*\*Submitting author:\*\*\s*.(@\S*)/)[1]

    # If the reminder is for the author then send the reminder, regardless
    # of the state of the reviewer checklists. Otherwise, check if they
    # need a reminder.
    if human.strip == author
      bg_respond(nwo, issue_id, ":wave: #{human}, please update us on how things are progressing here.")
    else
      if needs_reminder?(nwo, issue.body, human)
        bg_respond(nwo, issue_id, ":wave: #{human}, please update us on how your review is going.")
      end
    end
  end
end

class DOIWorker
  require_relative 'github'
  require_relative 'config_helper'

  require 'faraday'
  require 'ostruct'
  require 'serrano'
  require 'sidekiq'
  require 'uri'
  require 'whedon'
  require 'yaml'

  include Sidekiq::Worker

  sidekiq_options retry: false

  # Sets the Whedon environment
  include ConfigHelper
  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(nwo, issue_id, config, custom_branch, clear_cache=false)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Trying to debug a race condition on Heroku
    sleep(10)
    # Download the paper
    stdout, stderr, status = download(issue_id, clear_cache)

    if status.success?
      # Need to checkout the new branch before looking for the paper.
      `cd tmp/#{issue_id} && git checkout #{custom_branch} --quiet && cd` if custom_branch

      paper_path = find_paper(issue_id)
      if paper_path.end_with?('.tex')
        meta_data_path = "#{File.dirname(paper_path)}/paper.yml"
        bibtex_filename = YAML.load_file(meta_data_path)['bibliography']
      else
        bibtex_filename = YAML.load_file(paper_path)['bibliography']
      end

      bibtex_path = "#{File.dirname(paper_path)}/#{bibtex_filename}"

      if bibtex_path
        begin
          entries = BibTeX.open(bibtex_path, :filter => :latex)
        rescue BibTeX::ParseError => e
          bg_respond(nwo, issue_id, "Checking the BibTeX entries failed with the following error: \n\n #{e.message}") and return
        end

        doi_summary = check_dois(entries)

        if doi_summary.any?
          message = "```\nReference check summary (note 'MISSING' DOIs are suggestions that need verification):\n"
          doi_summary.each do |type, messages|
            message << "\n#{type.to_s.upcase} DOIs\n\n"
            if messages.empty?
              message << "- None\n"
            else
              messages.each {|m| message << "- #{m}\n"}
            end
          end
          message << "```"
          bg_respond(nwo, issue_id, message)
        else
          bg_respond(nwo, issue_id, "No immediate problems found with references.")
        end
      else
        bg_respond(nwo, issue_id, "Can't find a bibtex file for this submission")
      end
    else
      bg_respond(nwo, issue_id, "Downloading of the repository (to check the bibtex) failed for issue ##{issue_id} failed with the following error: \n\n #{stderr}") and return
    end
  end

  # How different are two strings?
  # https://en.wikipedia.org/wiki/Levenshtein_distance
  def levenshtein_distance(s, t)
    m = s.length
    n = t.length

    return m if n == 0
    return n if m == 0
    d = Array.new(m+1) {Array.new(n+1)}

    (0..m).each {|i| d[i][0] = i}
    (0..n).each {|j| d[0][j] = j}
    (1..n).each do |j|
      (1..m).each do |i|
        d[i][j] = if s[i-1] == t[j-1]  # adjust index into string
                    d[i-1][j-1]       # no operation required
                  else
                    [ d[i-1][j]+1,    # deletion
                      d[i][j-1]+1,    # insertion
                      d[i-1][j-1]+1,  # substitution
                    ].min
                  end
      end
    end

    d[m][n]
  end

  def crossref_lookup(query_value)
    puts "Crossref query value is #{query_value}"
    works = Serrano.works(:query => query_value)
    if works['message'].any? && works['message']['items'].any?
      if works['message']['items'].first.has_key?('DOI')
        candidate = works['message']['items'].first
        return nil unless candidate['title']
        candidate_title = candidate['title'].first.downcase
        candidate_doi = candidate['DOI']
        distance = levenshtein_distance(candidate_title, query_value.downcase)

        if distance < 3
          return candidate_doi
        else
          return nil
        end
      end
    end
  end

  # TODO: refactor this monster. Soon...
  def check_dois(entries)
    doi_summary = {:ok => [], :missing => [], :invalid => []}

    if entries.any?
      entries.each do |entry|
        next if entry.comment?
        next if entry.preamble?

        if entry.has_field?('doi') && !entry.doi.empty?
          if invalid_doi?(entry.doi)
            if entry.doi.to_s.include?('http')
              doi_summary[:invalid].push("#{entry.doi} is INVALID because of 'https://doi.org/' prefix")
            else
              doi_summary[:invalid].push("#{entry.doi} is INVALID")
            end
          else
            doi_summary[:ok].push("#{entry.doi} is OK")
          end
        # If there's no DOI present, check Crossref to see if we can find a candidate DOI for this entry.
        else
          if entry.has_field?('title')
            if candidate_doi = crossref_lookup(entry.title.value)
              doi_summary[:missing].push("#{candidate_doi} may be a valid DOI for title: #{entry.title}")
            end
          end
        end
      end
    end

    return doi_summary
  end

  # Return true if the DOI doesn't resolve properly
  def invalid_doi?(doi_string)
    return true if doi_string.nil?

    if doi_string.include?('http')
      return true
    else
      url = "https://doi.org/#{doi_string}"
    end

    escaped_url = URI.escape(url)

    begin
      status_code = Faraday.head(escaped_url).status
      if [301, 302].include? status_code
        return false
      else
        return true
      end
    rescue Faraday::ConnectionFailed
      return true
    rescue URI::InvalidURIError
      return true
    end
  end

  def find_paper(issue_id)
    search_path ||= "tmp/#{issue_id}"
    paper_paths = []

    Find.find(search_path) do |path|
      paper_paths << path if path =~ /paper\.tex$|paper\.md$/
    end

    return paper_paths.first
  end

  def download(issue_id, clear_cache)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}") if clear_cache
    Open3.capture3("whedon download #{issue_id}")
  end
end

class RepoWorker
  require_relative 'github'
  require_relative 'config_helper'

  require 'ostruct'
  require 'rugged'
  require 'licensee'
  require 'linguist'
  require 'sidekiq'

  include Sidekiq::Worker
  sidekiq_options retry: false

  # Sets the Whedon environment
  include ConfigHelper
  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(nwo, issue_id, config)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Download the paper
    stdout, stderr, status = download(issue_id)

    if status.success?
      languages = detect_languages(issue_id)
      license = detect_license(issue_id)
      detect_statement_of_need(nwo, issue_id)
      repo_summary(nwo, issue_id)
      label_issue(nwo, issue_id, languages) if languages.any?
      bg_respond(nwo, issue_id, "Failed to discover a valid open source license.") if license.nil?
    else
      bg_respond(nwo, issue_id, "Downloading of the repository (to analyze the language) for issue ##{issue_id} failed with the following error: \n\n #{stderr}") and return
    end
  end

  def repo_summary(nwo, issue_id)
    result, stderr, status = Open3.capture3("cd tmp/#{issue_id} && cloc --quiet .")

    message = "```\nSoftware report (experimental):\n"

    if status.success?
      message << "#{result}"
    end

    result, stderr, status = Open3.capture3("cd tmp/#{issue_id} && PYTHONIOENCODING=utf-8 gitinspector .")

    if status.success?
      message << "\n\n#{result}```"
    end

    bg_respond(nwo, issue_id, message)
  end

  def detect_license(issue_id)
    return Licensee.project("tmp/#{issue_id}").license
  end

  def detect_languages(issue_id)
    repo = Rugged::Repository.new("tmp/#{issue_id}")
    project = Linguist::Repository.new(repo, repo.head.target_id)

    # Take top three languages from Linguist
    project.languages.keys.take(3)
  end

  def detect_statement_of_need(nwo, issue_id)
    paper_paths = find_paper_paths("tmp/#{issue_id}")

    return if paper_paths.empty?

    puts "CHECKING STATEMENT OF NEED"

    # Does the paper include 'statement of need'
    unless File.open(paper_paths.first).read() =~ /# Statement of Need/i
      puts "FIRST PAPER IS #{paper_paths.first}"
      bg_respond(nwo, issue_id, "Failed to discover a `Statement of need` section in paper")
    end
  end

  def download(issue_id)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
  end

  def find_paper_paths(search_path=nil)
    search_path ||= "tmp/#{review_issue_id}"
    paper_paths = []

    Find.find(search_path) do |path|
      paper_paths << path if path =~ /\bpaper\.tex$|\bpaper\.md$/
    end

    return paper_paths
  end
end

# This is the Sidekiq worker that processes PDFs. It leverages the Whedon gem to
# carry out the majority of its actions. Where possible, we try and capture
# errors from any of the executed tasks and report them back to the review issue
class PDFWorker
  require_relative 'github'
  require_relative 'config_helper'

  require 'open3'
  require 'ostruct'
  require 'sidekiq'

  include Sidekiq::Worker
  sidekiq_options retry: false

  # Sets the Whedon environment
  include ConfigHelper
  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(nwo, issue_id, config, custom_branch, clear_cache=false)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Compile the paper
    pdf_path, stderr, status = download_and_compile(issue_id, custom_branch, clear_cache)

    if !status.success?
      bg_respond(nwo, issue_id, "PDF failed to compile for issue ##{issue_id} with the following error: \n\n #{stderr}") and return
    end

    # If we've got this far then push a copy of the PDF to the papers repository
    create_or_update_git_branch(issue_id, config.papers_repo, config.journal_alias)

    pdf_url, pdf_download_url = create_git_pdf(pdf_path, issue_id, config.papers_repo, config.journal_alias)

    pdf_response = ":point_right::page_facing_up: [Download article proof](#{pdf_download_url}) :page_facing_up: [View article proof on GitHub](#{pdf_url}) :page_facing_up: :point_left:"

    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pdf_response)
  end

  # Use the Whedon gem to download the software to a local tmp directory
  def download_and_compile(issue_id, custom_branch=nil, clear_cache)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}") if clear_cache

    result, stderr, status = Open3.capture3("whedon download #{issue_id}")

    if !status.success?
      return result, stderr, status
    end

    if custom_branch
      Open3.capture3("whedon prepare #{issue_id} #{custom_branch}")
    else
      Open3.capture3("whedon prepare #{issue_id}")
    end
  end
end

# This is the Sidekiq worker that processes PDFs. It leverages the Whedon gem to
# carry out the majority of its actions. Where possible, we try and capture
# errors from any of the executed tasks and report them back to the review issue
class DepositWorker
  require_relative 'github'
  require_relative 'config_helper'

  require 'open3'
  require 'ostruct'
  require 'sidekiq'
  require 'twitter'

  include Sidekiq::Worker
  sidekiq_options retry: false

  # Sets the Whedon environment
  include ConfigHelper
  # Include to communicate from background worker to GitHub
  include GitHub

  def perform(nwo, issue_id, config, custom_branch, dry_run)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Download and compile the paper
    pdf_path, stderr, status = download_and_compile(issue_id, custom_branch)

    if !status.success?
      bg_respond(nwo, issue_id, "PDF failed to compile for issue ##{issue_id} with the following error: \n\n #{stderr}") and return
    end

    # If we've got this far then push a copy of the PDF to the papers repository
    create_or_update_git_branch(issue_id, config.papers_repo, config.journal_alias)

    pdf_url, pdf_download_url = create_git_pdf(pdf_path, issue_id, config.papers_repo, config.journal_alias)

    crossref_xml_path = pdf_path.gsub('.pdf', '.crossref.xml')
    crossref_url = create_git_xml(crossref_xml_path, issue_id, config.papers_repo, config.journal_alias)

    if dry_run == true
      pr_url = create_deposit_pr(issue_id, config.papers_repo, config.journal_alias, dry_run)

      if custom_branch
        pr_response = ":wave: @#{config.eic_team_name}, this paper is ready to be accepted and published.\n\n Check final proof :point_right: #{pr_url}\n\nIf the paper PDF and Crossref deposit XML look good in #{pr_url}, then you can now move forward with accepting the submission by compiling again with the flag `deposit=true` e.g.\n ```\n@roboneuro accept deposit=true from branch #{custom_branch} \n```"
      else
        pr_response = ":wave: @#{config.eic_team_name}, this paper is ready to be accepted and published.\n\n Check final proof :point_right: #{pr_url}\n\nIf the paper PDF and Crossref deposit XML look good in #{pr_url}, then you can now move forward with accepting the submission by compiling again with the flag `deposit=true` e.g.\n ```\n@roboneuro accept deposit=true\n```"
      end
    else
      pr_url = create_deposit_pr(issue_id, config.papers_repo, config.journal_alias, dry_run)

      # Deposit with journal and Crossref
      deposit(issue_id)

      id = "%05d" % issue_id
      doi = "https://doi.org/#{config.doi_prefix}/#{config.journal_alias}.#{id}"

      pr_response = "🚨🚨🚨 **THIS IS NOT A DRILL, YOU HAVE JUST ACCEPTED A PAPER INTO #{config.journal_alias.upcase}!** 🚨🚨🚨\n\n Here's what you must now do:\n\n0. Check final PDF and Crossref metadata that was deposited :point_right: #{pr_url}\n1. Wait a couple of minutes to verify that the paper DOI resolves [#{doi}](#{doi})\n2. If everything looks good, then close this review issue.\n3. Party like you just published a paper! 🎉🌈🦄💃👻🤘\n\n Any issues? Notify your editorial technical team..."

      # Only Tweet if configured with keys
      if config.twitter_consumer_key
        whedon_tweet(crossref_xml_path, nwo, issue_id, config)
      end
    end
    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pr_response)
  end

  def whedon_tweet(crossref_xml_path, nwo, issue_id, config)
    # Read the XML
    doc = Nokogiri(File.open(crossref_xml_path.strip))
    # Extract the DOI
    doi = doc.css('publisher_item identifier').first.content
    # And the paper title
    title = doc.css('journal_article titles title').first.content

    tweet = %Q(Just published in ##{config.journal_alias}: '#{title}')

    client = Twitter::REST::Client.new do |c|
      c.consumer_key        = config.twitter_consumer_key
      c.consumer_secret     = config.twitter_consumer_secret
      c.access_token        = config.twitter_access_token
      c.access_token_secret = config.twitter_access_token_secret
    end

    t = client.update(tweet)
    response = "🐦🐦🐦 👉 [Tweet for this paper](#{t.uri.to_s}) 👈 🐦🐦🐦"
    bg_respond(nwo, issue_id, response)
  end

  # Use the Whedon gem to download the software to a local tmp directory
  def download_and_compile(issue_id, custom_branch=nil, clear_cache=true)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}") if clear_cache

    result, stderr, status = Open3.capture3("whedon download #{issue_id}")

    if !status.success?
      return result, stderr, status
    end

    if custom_branch
      Open3.capture3("whedon compile #{issue_id} #{custom_branch}")
    else
      Open3.capture3("whedon compile #{issue_id}")
    end
  end

  def deposit(issue_id)
    Open3.capture3("whedon deposit #{issue_id}")
  end
end

# This is the Sidekiq worker that processes Jupyter Books.
# Where possible, we try and capture errors from any of the
# executed tasks and report them back to the review issue.
class JBWorker
  require_relative 'github'
  require_relative 'config_helper'

  require 'open3'
  require 'ostruct'
  require 'sidekiq'
  require 'whedon'

  include Sidekiq::Worker
  sidekiq_options retry: false

  # Sets the Whedon environment
  include ConfigHelper
  # Include to communicate from background worker to GitHub
  include GitHub

  def perform(nwo, issue_id, config, custom_branch, clear_cache=false)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Trying to debug a race condition on Heroku, following PDFWorker
    sleep(10)
    # Download the notebooks
    stdout, stderr, status = download(issue_id, clear_cache)

    if status.success?
      # Need to checkout the new branch before looking for the Jupyter Book.
      `cd tmp/#{issue_id} && git checkout #{custom_branch} --quiet && cd` if custom_branch

      jb_path = find_jb(issue_id)
      result, stderr, status = Open3.capture3("pip install -r #{jb_path}/requirements.txt && jupyter-book build #{jb_path}")
    else
      bg_respond(nwo, issue_id, "Jupyter Book failed to compile for issue ##{issue_id} with the following error: \n\n #{stderr}") and return
    end

    # If we've got this far then push a copy of the built site to the papers repository
    create_or_update_git_branch(issue_id, config.papers_repo, config.journal_alias)

    book_url, book_download_url = create_git_pdf(pdf_path, issue_id, config.papers_repo, config.journal_alias)

    book_response = ":point_right::page_facing_up: [Download article proof](#{pdf_download_url}) :page_facing_up: [View article proof on GitHub](#{pdf_url}) :page_facing_up: :point_left:"

    # Finally, respond in the review issue with the Jupyter Book URL
    bg_respond(nwo, issue_id, book_response)
  end

  def download(issue_id, clear_cache)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}") if clear_cache
    Open3.capture3("whedon download #{issue_id}")
  end

  def find_jb(issue_id)
    search_path ||= "tmp/#{issue_id}"
    jb_paths = []

    Find.find(search_path) do |path|
      jb_paths << path if path =~ /_toc\.yml$|_config\.yml$/
    end

    return jb_paths.first
  end
end