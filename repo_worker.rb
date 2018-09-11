# This worker runs Linguist (https://github.com/github/linguist) on the software
# being reviewed and adds labels to the PRE-REVIEW issue for the top three
# detected languages.
# In addition, it tries to detect an open source license. If it doesn't find one
# it will complain.

class RepoWorker
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

  # This method allows the background worker to post messages to GitHub.
  def bg_respond(nwo, issue_id, comment)
    github_client.add_comment(nwo, issue_id, comment)
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
  def set_env(nwo, journal_launch_date)
    ENV['REVIEW_REPOSITORY'] = nwo
    ENV['JOURNAL_LAUNCH_DATE'] = journal_launch_date
  end
end
