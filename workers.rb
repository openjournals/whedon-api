class RepoWorker
  require_relative 'github'

  require 'rugged'
  require 'licensee'
  require 'linguist'
  require 'sidekiq'

  include Sidekiq::Worker

  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(nwo, issue_id, journal_launch_date)
    set_env(nwo, journal_launch_date)

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
    puts "Downloading #{ENV['REVIEW_REPOSITORY']}"
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
  end

  # The Whedon gem expects a bunch of environment variables to be available
  # and this method sets them.
  def set_env(nwo, journal_launch_date)
    ENV['REVIEW_REPOSITORY'] = nwo
    ENV['JOURNAL_LAUNCH_DATE'] = journal_launch_date
  end
end

# This is the Sidekiq worked that processes PDFs. It leverages the Whedon gem to
# carry out the majority of its actions. Where possible, we try and capture
# errors from any of the executed tasks and report them back to the review issue
class PDFWorker
  require_relative 'github'
  require 'open3'
  require 'sidekiq'

  include Sidekiq::Worker

  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(papers_repo, custom_branch, site_host, site_name, nwo, issue_id, journal_alias, journal_launch_date)
    set_env(papers_repo, site_host, site_name, journal_alias, journal_launch_date, nwo)

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
    puts "Creating Git branch"
    create_or_update_git_branch(issue_id, papers_repo, journal_alias)

    puts "Uploading #{pdf_path}"
    pdf_url = create_git_pdf(pdf_path, issue_id, papers_repo, journal_alias)

    pdf_response = "[ :point_right: Check article proof :page_facing_up: :point_left: ](#{pdf_url})"

    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pdf_response)
  end

  # Use the Whedon gem to download the software to a local tmp directory
  def download(issue_id)
    puts "Downloading #{ENV['REVIEW_REPOSITORY']}"
    FileUtils.rm_rf("tmp/#{issue_id}") if Dir.exist?("tmp/#{issue_id}")
    Open3.capture3("whedon download #{issue_id}")
  end

  # Use the Whedon gem to compile the paper
  def compile(issue_id, custom_branch=nil)
    puts "Compiling #{ENV['REVIEW_REPOSITORY']}/#{issue_id}"
    if custom_branch
      Open3.capture3("whedon prepare #{issue_id} #{custom_branch}")
    else
      Open3.capture3("whedon prepare #{issue_id}")
    end
  end

  # The Whedon gem expects a bunch of environment variables to be available
  # and this method sets them.
  def set_env(papers, site_host, site_name, journal_alias, journal_launch_date, nwo)
    ENV['REVIEW_REPOSITORY'] = nwo
    ENV['DOI_PREFIX'] = "10.21105"
    ENV['JOURNAL_ALIAS'] = journal_alias
    ENV['PAPER_REPOSITORY'] = papers
    ENV['JOURNAL_URL'] = site_host
    ENV['JOURNAL_NAME'] = site_name
    ENV['JOURNAL_LAUNCH_DATE'] = journal_launch_date
  end
end

# This is the Sidekiq worked that processes PDFs. It leverages the Whedon gem to
# carry out the majority of its actions. Where possible, we try and capture
# errors from any of the executed tasks and report them back to the review issue
class DepositWorker
  require_relative 'github'
  require 'open3'
  require 'sidekiq'

  include Sidekiq::Worker

  # Including this means we can talk to GitHub from the background worker.
  include GitHub

  def perform(papers_repo, site_host, site_name, nwo, issue_id, journal_alias, journal_issn, journal_launch_date, dry_run, crossref_username, crossref_password, whedon_secret)

    set_env(papers_repo, site_host, site_name, journal_alias, journal_issn, journal_launch_date, nwo, crossref_username, crossref_password, whedon_secret)

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
    puts "Creating Git branch"
    create_or_update_git_branch(issue_id, papers_repo, journal_alias)

    puts "Uploading #{pdf_path}"
    pdf_url = create_git_pdf(pdf_path, issue_id, papers_repo, journal_alias)

    crossref_xml_path = pdf_path.gsub('.pdf', '.crossref.xml')
    puts "Uploading #{crossref_xml_path}"
    crossref_url = create_git_xml(crossref_xml_path, issue_id, papers_repo, journal_alias)

    if dry_run == true
      pr_url = create_deposit_pr(issue_id, papers_repo, journal_alias, dry_run)

      pr_response = "Check final proof :point_right: #{pr_url}\n\nIf the paper PDF and Crossref deposit XML look good in #{pr_url}, then you can now move forward with accepting the submission by compiling again with the flag `deposit=true` e.g.\n ```\n@whedon accept deposit=true\n```"
    else
      pr_url = create_deposit_pr(issue_id, papers_repo, journal_alias, dry_run)

      # Deposit with journal and Crossref
      deposit(issue_id)

      id = "%05d" % issue_id
      doi = "https://doi.org/#{ENV['DOI_PREFIX']}/#{journal_alias}.#{id}"

      pr_response = "🚨🚨🚨 **THIS IS NOT A DRILL, YOU HAVE JUST ACCEPTED A PAPER INTO #{journal_alias.upcase}!** 🚨🚨🚨\n\n Here's what you must now do:\n\n0. Check final PDF and Crossref metadata that was deposited :point_right: #{pr_url}\n1. Wait a couple of minutes to verify that the paper DOI resolves [#{doi}](#{doi})\n2. If everything looks good, then close this review issue.\n3. Party like you just published a paper! 🎉🌈🦄💃👻🤘\n\n Any issues? notify your editorial technical team..."
    end
    # Finally, respond in the review issue with the PDF URL
    bg_respond(nwo, issue_id, pr_response)
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
    Open3.capture3("whedon compile #{issue_id}")
  end

  def deposit(issue_id)
    puts "Depositing #{ENV['REVIEW_REPOSITORY']}/#{issue_id} with Crossref and JOSS"
    Open3.capture3("whedon deposit #{issue_id}")
  end

  # The Whedon gem expects a bunch of environment variables to be available
  # and this method sets them.
  def set_env(papers, site_host, site_name, journal_alias, journal_issn, journal_launch_date, nwo, crossref_username, crossref_password, whedon_secret)
    ENV['REVIEW_REPOSITORY'] = nwo
    ENV['DOI_PREFIX'] = "10.21105"
    ENV['JOURNAL_ALIAS'] = journal_alias
    ENV['PAPER_REPOSITORY'] = papers
    ENV['JOURNAL_URL'] = site_host
    ENV['JOURNAL_NAME'] = site_name
    ENV['JOURNAL_ISSN'] = journal_issn
    ENV['JOURNAL_LAUNCH_DATE'] = journal_launch_date
    ENV['CROSSREF_USERNAME'] = crossref_username
    ENV['CROSSREF_PASSWORD'] = crossref_password
    ENV['WHEDON_SECRET'] = whedon_secret
  end
end
