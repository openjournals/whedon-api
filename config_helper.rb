require 'ostruct'

module ConfigHelper
  def set_env(nwo, issue_id, config)
    config = OpenStruct.new(config)

    ENV['REVIEW_REPOSITORY'] = nwo
    ENV['DOI_PREFIX'] = config.doi_prefix
    ENV['JOURNAL_ALIAS'] = config.doi_journal
    ENV['PAPER_REPOSITORY'] = config.papers
    ENV['JOURNAL_URL'] = config.site_host
    ENV['JOURNAL_NAME'] = config.site_name
    ENV['JOURNAL_ISSN'] = config.journal_issn
    ENV['JOURNAL_LAUNCH_DATE'] = config.journal_launch_date
    ENV['CROSSREF_USERNAME'] = config.crossref_username
    ENV['CROSSREF_PASSWORD'] = config.crossref_password
    ENV['WHEDON_SECRET'] = config.whedon_secret
  end
end
