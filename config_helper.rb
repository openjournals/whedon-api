# This module defines a whole bunch of environment variables that are required
# by the Whedon gem when executing tasks.

module ConfigHelper
  def set_env(nwo, issue_id, config)
    ENV['REVIEW_REPOSITORY'] = nwo
    ENV['DOI_PREFIX'] = config.doi_prefix
    ENV['JOURNAL_ALIAS'] = config.journal_alias
    ENV['PAPER_REPOSITORY'] = config.papers_repo
    ENV['JOURNAL_URL'] = config.site_host
    ENV['JOURNAL_NAME'] = config.site_name
    ENV['CURRENT_ISSUE'] = config.current_issue
    ENV['JOURNAL_VOLUME'] = config.current_volume
    ENV['JOURNAL_ISSN'] = config.journal_issn
    ENV['JOURNAL_LAUNCH_DATE'] = config.journal_launch_date
    ENV['CROSSREF_USERNAME'] = config.crossref_username
    ENV['CROSSREF_PASSWORD'] = config.crossref_password
    ENV['WHEDON_SECRET'] = config.site_api_key
  end
end
