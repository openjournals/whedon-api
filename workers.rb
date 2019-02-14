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
      if needs_reminder?(issue_body, human)
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
      paper_path = find_paper(issue_id)
      bibtex_filename = YAML.load_file(paper_path)['bibliography']
      bibtex_path = "#{File.dirname(paper_path)}/#{bibtex_filename}"

      if bibtex_path
        doi_summary = check_dois(bibtex_path)
        if doi_summary.any?
          message = "```Reference check summary:\n"
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

  def check_dois(bibtex_path)
    doi_summary = {:ok => [], :missing => [], :invalid => []}
    entries = BibTeX.open(bibtex_path, :filter => :latex)

    if entries.any?
      entries.each do |entry|
        next if entry.comment?
        next unless entry.article?

        if entry.has_field?('doi') && !entry.doi.empty?
          if invalid_doi?(entry.doi)
            doi_summary[:invalid].push("http://doi.org/#{entry.doi} is INVALID")
          else
            doi_summary[:ok].push("http://doi.org/#{entry.doi} is OK")
          end
        # If there's no DOI present, check Crossref to see if we can find a candidate DOI for this entry.
        else
          # Do inject or something fancy here to build comma-separated string
          query_value = entry.collect {|_, value| value}.join(', ')
          works = Serrano.works(:query => query_value)
          if works['message']['items'].any?
            if works['message']['items'].first.has_key?('DOI')
              candidate_doi = works['message']['items'].first['DOI']
              doi_summary[:missing].push("https://doi.org/#{candidate_doi} may be missing for title: #{entry.title}")
            end
          end
        end
      end
    end

    return doi_summary
  end

  # Return true if the DOI doesn't resolve properly
  def invalid_doi?(doi_string)
    doi = doi_string.to_s[/\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'])\S)+)\b/]

    return true if doi.nil?

    url = "https://doi.org/#{doi.strip}"
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
    end
  end

  def find_paper(issue_id)
    search_path ||= "tmp/#{issue_id}"
    paper_paths = []

    Find.find(search_path) do |path|
      paper_paths << path if path =~ /paper\.md$/
    end

    return paper_paths.first
  end

  def download(issue_id)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
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
      label_issue(nwo, issue_id, languages) if languages.any?
      bg_respond(nwo, issue_id, "Failed to discover a valid open source license.") if license.nil?
    else
      bg_respond(nwo, issue_id, "Downloading of the repository (to analyze the language) for issue ##{issue_id} failed with the following error: \n\n #{stderr}") and return
    end
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

  def download(issue_id)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
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

  # Sets the Whedon environment
  include ConfigHelper
  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(nwo, issue_id, config, custom_branch)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Download the paper
    stdout, stderr, status = download(issue_id)

    # Whedon often can't find a paper in the repository he's downloaded even
    # though it's definitely there (e.g. https://github.com/openjournals/joss-reviews/issues/776#issuecomment-397714563)
    # Not sure if this is because the repository hasn't downloaded yet.
    # Adding in a sleep statement to see if this helps.
    sleep(5)

    if !status.success?
      bg_respond(nwo, issue_id, "Downloading of the repository for issue ##{issue_id} failed with the following error: \n\n #{stderr}") and return
    end

    # Compile the paper
    pdf_path, stderr, status = compile(issue_id, custom_branch)

    if !status.success?
      bg_respond(nwo, issue_id, "PDF failed to compile for issue ##{issue_id} with the following error: \n\n #{stderr}") and return
    end

    # If we've got this far then push a copy of the PDF to the papers repository
    create_or_update_git_branch(issue_id, config.papers_repo, config.journal_alias)

    pdf_url = create_git_pdf(pdf_path, issue_id, config.papers_repo, config.journal_alias)

    pdf_response = "[ :point_right: Check article proof :page_facing_up: :point_left: ](#{pdf_url})"

    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pdf_response)
  end

  # Use the Whedon gem to download the software to a local tmp directory
  def download(issue_id)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
  end

  # Use the Whedon gem to compile the paper
  def compile(issue_id, custom_branch=nil)
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

  include Sidekiq::Worker

  # Sets the Whedon environment
  include ConfigHelper
  # Include to communicate from background worker to GitHub
  include GitHub

  def perform(nwo, issue_id, config, dry_run)
    config = OpenStruct.new(config)
    set_env(nwo, issue_id, config)

    # Download the paper
    stdout, stderr, status = download(issue_id)

    # Whedon often can't find a paper in the repository he's downloaded even
    # though it's definitely there (e.g. https://github.com/openjournals/joss-reviews/issues/776#issuecomment-397714563)
    # Not sure if this is because the repository hasn't downloaded yet.
    # Adding in a sleep statement to see if this helps.
    sleep(5)

    if !status.success?
      bg_respond(nwo, issue_id, "Downloading of the repository for issue ##{issue_id} failed with the following error: \n\n #{stderr}") and return
    end

    # Compile the paper
    pdf_path, stderr, status = compile(issue_id)

    if !status.success?
      bg_respond(nwo, issue_id, "PDF failed to compile for issue ##{issue_id} with the following error: \n\n #{stderr}") and return
    end

    # If we've got this far then push a copy of the PDF to the papers repository
    create_or_update_git_branch(issue_id, config.papers_repo, config.journal_alias)

    pdf_url = create_git_pdf(pdf_path, issue_id, config.papers_repo, config.journal_alias)

    crossref_xml_path = pdf_path.gsub('.pdf', '.crossref.xml')
    crossref_url = create_git_xml(crossref_xml_path, issue_id, config.papers_repo, config.journal_alias)

    if dry_run == true
      pr_url = create_deposit_pr(issue_id, config.papers_repo, config.journal_alias, dry_run)

      pr_response = "Check final proof :point_right: #{pr_url}\n\nIf the paper PDF and Crossref deposit XML look good in #{pr_url}, then you can now move forward with accepting the submission by compiling again with the flag `deposit=true` e.g.\n ```\n@whedon accept deposit=true\n```"
    else
      pr_url = create_deposit_pr(issue_id, config.papers_repo, config.journal_alias, dry_run)

      # Deposit with journal and Crossref
      deposit(issue_id)

      id = "%05d" % issue_id
      doi = "https://doi.org/#{config.doi_prefix}/#{config.journal_alias}.#{id}"

      pr_response = "🚨🚨🚨 **THIS IS NOT A DRILL, YOU HAVE JUST ACCEPTED A PAPER INTO #{config.journal_alias.upcase}!** 🚨🚨🚨\n\n Here's what you must now do:\n\n0. Check final PDF and Crossref metadata that was deposited :point_right: #{pr_url}\n1. Wait a couple of minutes to verify that the paper DOI resolves [#{doi}](#{doi})\n2. If everything looks good, then close this review issue.\n3. Party like you just published a paper! 🎉🌈🦄💃👻🤘\n\n Any issues? notify your editorial technical team..."
    end
    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pr_response)
  end

  # Use the Whedon gem to download the software to a local tmp directory
  def download(issue_id)
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
  end

  # Use the Whedon gem to compile the paper
  def compile(issue_id)
    Open3.capture3("whedon compile #{issue_id}")
  end

  def deposit(issue_id)
    Open3.capture3("whedon deposit #{issue_id}")
  end
end
