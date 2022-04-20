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
    # We need this for NeuroLibre as its abbrv name is not 
    # all uppercaser of the alias as in JOSS.
    # Addedd in roboneuro-gem v 1.0.4
    ENV['JOURNAL_ABBRV_TITLE'] = config.journal_abbrv_name
    ENV['CURRENT_ISSUE'] = config.current_issue
    ENV['CURRENT_VOLUME'] = config.current_volume
    ENV['CURRENT_YEAR'] = Time.now.year.to_s
    ENV['JOURNAL_ISSN'] = config.journal_issn
    ENV['JOURNAL_LAUNCH_DATE'] = config.journal_launch_date
    ENV['CROSSREF_USERNAME'] = config.crossref_username
    ENV['CROSSREF_PASSWORD'] = config.crossref_password
    ENV['WHEDON_SECRET'] = config.site_api_key
  end
end
