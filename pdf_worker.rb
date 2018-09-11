# This is the Sidekiq worked that processes PDFs. It leverages the Whedon gem to
# carry out the majority of its actions. Where possible, we try and capture
# errors from any of the executed tasks and report them back to the review issue
class PDFWorker
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

  # This method allows the background worker to post messages to GitHub.
  def bg_respond(nwo, issue_id, comment)
    github_client.add_comment(nwo, issue_id, comment)
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

    puts "FILE PATH IS #{file_path}"
    puts `cat #{file_path }`
    gh_response = github_client.create_contents(papers_repo,
                                                pdf_path,
                                                "Creating 10.21105.#{journal_alias}.#{id}.pdf",
                                                File.open("#{file_path.strip}").read,
                                                :branch => "#{journal_alias}.#{id}")

    return gh_response.content.html_url
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
