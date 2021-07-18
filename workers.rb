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
    ENV["JOURNAL_LAUNCH_DATE"] = '2016-05-05'

    result, stderr, status = Open3.capture3("git ls-remote #{repository_address}")

    if !status.success?
      self.payload = "Invalid Git repository address. Check that the repository can be cloned using the value entered in the form, and that access doesn't require authentication."
      abort("Can't access that repository address")
    end

    if custom_branch
      result, stderr, status = Open3.capture3("cd tmp && git clone --single-branch --branch #{custom_branch} #{repository_address} #{sha}")
    else
      result, stderr, status = Open3.capture3("cd tmp && git clone #{repository_address} #{sha}")
    end

    if !status.success?
      return result, stderr, status
    end

    paper_paths = find_paper_paths("tmp/#{sha}")

    if journal == "JOSS"
      journal_name = "Journal of Open Source Software"
    elsif journal == "JOSE"
      journal_name = "Journal of Open Source Education"
    end

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

      result, stderr, status = Open3.capture3("cd #{directory} && pandoc -V repository='#{repository_address}' -V archive_doi='PENDING' -V paper_url='PENDING' -V journal_name='#{journal_name}' -V formatted_doi='10.21105/#{journal}.0XXXX' -V review_issue_url='XXXX' -V graphics='true' -V issue='X' -V volume='X' -V page='X' -V logo_path='#{Whedon.resources}/#{journal}/logo.png' -V aas_logo_path='#{Whedon.resources}/#{journal}/aas-logo.png' -V year='XXXX' -V submitted='01 January XXXX' -V published='01 January XXXX' -V editor_name='Editor Name' -V editor_url='http://example.com' -V citation_author='Mickey Mouse et al.' -V draft=true -o #{sha}.pdf -V geometry:margin=1in --pdf-engine=xelatex --citeproc #{File.basename(paper_paths.first)} --from markdown+autolink_bare_uris --csl=#{csl_file} --template #{latex_template_path}")

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
      bg_respond(nwo, issue_id, ":wave: #{human}, please update us on how things are progressing here (this is an automated reminder).")
    else
      if needs_reminder?(nwo, issue.body, human)
        bg_respond(nwo, issue_id, ":wave: #{human}, please update us on how your review is going (this is an automated reminder).")
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

  def perform(nwo, issue_id, config, custom_branch)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Download the paper
    stdout, stderr, status = download(issue_id)

    if status.success?
      # Need to checkout the new branch before looking for the paper.
      `cd #{jid} && git checkout #{custom_branch} --quiet && cd` if custom_branch

      paper_path = find_paper(issue_id, jid)

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
      bg_respond(nwo, issue_id, "Downloading of the repository (to check the bibtex) failed for issue ##{issue_id} failed with the following error: \n```\n#{stderr}\n```") and return
    end

    # Clean-up
    FileUtils.rm_rf("#{jid}") if Dir.exist?("#{jid}")
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
        next if entry.string?

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
            begin
              if candidate_doi = crossref_lookup(entry.title.value)
                doi_summary[:missing].push("#{candidate_doi} may be a valid DOI for title: #{entry.title}")
              end
            rescue Serrano::InternalServerError
              # Do nothing, error from Crossref.
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

  def find_paper(issue_id, search_path)
    search_path ||= "tmp/#{issue_id}"
    paper_paths = []

    Find.find(search_path) do |path|
      paper_paths << path if path =~ /paper\.tex$|paper\.md$/
    end

    return paper_paths.first
  end

  def download(issue_id)
    Open3.capture3("whedon download #{issue_id} #{jid}")
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

  def perform(nwo, issue_id, config, custom_branch=nil)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Download the paper
    stdout, stderr, status = download(issue_id)

    if status.success?
      `cd #{jid} && git checkout #{custom_branch} --quiet && cd` if custom_branch

      languages = detect_languages(issue_id)
      license = detect_license(issue_id)
      detect_statement_of_need(nwo, issue_id)
      count_words(nwo, issue_id)
      repo_summary(nwo, issue_id)
      label_issue(nwo, issue_id, languages) if languages.any?
      bg_respond(nwo, issue_id, "Failed to discover a valid open source license.") if license.nil?
    else
      bg_respond(nwo, issue_id, "Downloading of the repository (to analyze the language) for issue ##{issue_id} failed with the following error: \n```\n #{stderr}\n```") and return
    end

    # Clean-up
    FileUtils.rm_rf("#{jid}") if Dir.exist?("#{jid}")
  end

  def repo_summary(nwo, issue_id)
    result, stderr, status = Open3.capture3("cd #{jid} && cloc --quiet .")

    message = "```\nSoftware report (experimental):\n"

    if status.success?
      message << "#{result}"
    end

    result, stderr, status = Open3.capture3("cd #{jid} && PYTHONIOENCODING=utf-8 gitinspector .")

    if status.success?
      message << "\n\n#{result}```"
    end

    bg_respond(nwo, issue_id, message)
  end

  def count_words(nwo, issue_id)
    paper_paths = find_paper_paths("#{jid}")

    return if paper_paths.empty?

    puts "CHECKING WORD COUNT"
    
    word_count = `cat #{paper_paths.first} | wc -w`.to_i

    bg_respond(nwo, issue_id, "Wordcount for `#{File.basename(paper_paths.first)}` is #{word_count}")
  end
  
  def detect_license(issue_id)
    return Licensee.project("#{jid}").license
  end

  def detect_languages(issue_id)
    repo = Rugged::Repository.new("#{jid}")
    project = Linguist::Repository.new(repo, repo.head.target_id)

    # Take top three languages from Linguist
    project.languages.keys.take(3)
  end

  def detect_statement_of_need(nwo, issue_id)
    paper_paths = find_paper_paths("#{jid}")

    return if paper_paths.empty?

    puts "CHECKING STATEMENT OF NEED"

    # Does the paper include 'statement of need'
    unless File.open(paper_paths.first).read() =~ /# Statement of Need/i
      puts "FIRST PAPER IS #{paper_paths.first}"
      bg_respond(nwo, issue_id, "Failed to discover a `Statement of need` section in paper")
    end
  end

  def download(issue_id)
    Open3.capture3("whedon download #{issue_id} #{jid}")
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

  def perform(nwo, issue_id, config, custom_branch)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Compile the paper
    pdf_path, stderr, status = download_and_compile(issue_id, custom_branch)

    if !status.success?
      # Clean-up
      FileUtils.rm_rf("#{jid}") if Dir.exist?("#{jid}")
      bg_respond(nwo, issue_id, "PDF failed to compile for issue ##{issue_id} with the following error: \n```\n #{stderr}\n```") and return
    end

    # If we've got this far then push a copy of the PDF to the papers repository
    create_or_update_git_branch(issue_id, config.papers_repo, config.journal_alias)

    pdf_url, pdf_download_url = create_git_pdf(pdf_path, issue_id, config.papers_repo, config.journal_alias)

    pdf_response = ":point_right::page_facing_up: [Download article proof](#{pdf_download_url}) :page_facing_up: [View article proof on GitHub](#{pdf_url}) :page_facing_up: :point_left:"

    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pdf_response)

    # Clean-up
    FileUtils.rm_rf("#{jid}") if Dir.exist?("#{jid}")
  end

  # Use the Whedon gem to download the software to a local tmp directory
  def download_and_compile(issue_id, custom_branch=nil)
    result, stderr, status = Open3.capture3("whedon download #{issue_id} #{jid}")

    if !status.success?
      return result, stderr, status
    end

    `cd #{jid} && git checkout #{custom_branch} --quiet && cd` if custom_branch
    Open3.capture3("whedon prepare #{issue_id} #{jid}")
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
      # Clean-up
      FileUtils.rm_rf("#{jid}") if Dir.exist?("#{jid}")
      bg_respond(nwo, issue_id, "PDF failed to compile for issue ##{issue_id} with the following error: \n```\n #{stderr}\n```") and return
    end

    # If we've got this far then push a copy of the PDF to the papers repository
    create_or_update_git_branch(issue_id, config.papers_repo, config.journal_alias)

    pdf_url, pdf_download_url = create_git_pdf(pdf_path, issue_id, config.papers_repo, config.journal_alias)

    crossref_xml_path = pdf_path.gsub('.pdf', '.crossref.xml')
    crossref_url = create_git_xml(crossref_xml_path, issue_id, config.papers_repo, config.journal_alias)

    if dry_run == true
      pr_url = create_deposit_pr(issue_id, config.papers_repo, config.journal_alias, dry_run)

      if custom_branch
        pr_response = ":wave: @#{config.eic_team_name}, this paper is ready to be accepted and published.\n\n Check final proof :point_right: #{pr_url}\n\nIf the paper PDF and Crossref deposit XML look good in #{pr_url}, then you can now move forward with accepting the submission by compiling again with the flag `deposit=true` e.g.\n ```\n@whedon accept deposit=true from branch #{custom_branch} \n```"
      else
        pr_response = ":wave: @#{config.eic_team_name}, this paper is ready to be accepted and published.\n\n Check final proof :point_right: #{pr_url}\n\nIf the paper PDF and Crossref deposit XML look good in #{pr_url}, then you can now move forward with accepting the submission by compiling again with the flag `deposit=true` e.g.\n ```\n@whedon accept deposit=true\n```"
      end
    else
      pr_url = create_deposit_pr(issue_id, config.papers_repo, config.journal_alias, dry_run)

      # Deposit with journal and Crossref
      deposit(issue_id)

      id = "%05d" % issue_id
      doi = "https://doi.org/#{config.doi_prefix}/#{config.journal_alias}.#{id}"

      pr_response = "🚨🚨🚨 **THIS IS NOT A DRILL, YOU HAVE JUST ACCEPTED A PAPER INTO #{config.journal_alias.upcase}!** 🚨🚨🚨\n\n Here's what you must now do:\n\n0. Check final PDF and Crossref metadata that was deposited :point_right: #{pr_url}\n1. Wait a couple of minutes, then verify that the paper DOI resolves [#{doi}](#{doi})\n2. If everything looks good, then close this review issue.\n3. Party like you just published a paper! 🎉🌈🦄💃👻🤘\n\n Any issues? Notify your editorial technical team..."

      # Only Tweet if configured with keys
      if config.twitter_consumer_key
        whedon_tweet(crossref_xml_path, nwo, issue_id, config)
      end
    end
    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pr_response)
    # Clean-up
    FileUtils.rm_rf("#{jid}") if Dir.exist?("#{jid}")
  end

  def whedon_tweet(crossref_xml_path, nwo, issue_id, config)
    # Read the XML
    doc = Nokogiri(File.open(crossref_xml_path.strip))
    # Extract the DOI
    doi = doc.css('publisher_item identifier').first.content
    # And the paper title
    title = doc.css('journal_article titles title').first.content

    tweet = %Q(Just published in ##{config.journal_alias.upcase}_theOJ: '#{title}' https://doi.org/#{doi})

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
  def download_and_compile(issue_id, custom_branch=nil)
    result, stderr, status = Open3.capture3("whedon download #{issue_id} #{jid}")

    if !status.success?
      return result, stderr, status
    end

    `cd #{jid} && git checkout #{custom_branch} --quiet && cd` if custom_branch

    Open3.capture3("whedon compile #{issue_id} #{jid}")
  end

  def deposit(issue_id)
    Open3.capture3("whedon deposit #{issue_id} #{jid}")
  end
end
