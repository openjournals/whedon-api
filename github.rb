require 'octokit'

module GitHub
  # Authenticated Octokit

  def github_client
    @github_client ||= Octokit::Client.new( :access_token => ENV['GH_TOKEN'],
                                            :auto_paginate => true)
  end

  # This method allows the background worker to post messages to GitHub.
  def bg_respond(nwo, issue_id, comment)
    github_client.add_comment(nwo, issue_id, comment)
  end

  def label_issue(nwo, issue_id, languages)
    github_client.add_labels_to_an_issue(nwo, issue_id, languages)
  end

  def get_master_ref(papers)
    github_client.refs(papers).select { |r| r[:ref] == "refs/heads/master" }.first.object.sha
  end

  # This method creates a branch on the papers_repo for the issue.
  # -- First it looks for files in the current branch
  # -- If it finds any, it deletes them.
  # -- Deletes the branch. Then recreates it.
  # -- If it doesn't find a branch for that issue. It simply creates one.
  def create_or_update_git_branch(issue_id, papers_repo, journal_alias)
    id = "%05d" % issue_id
    branch = "#{journal_alias}.#{id}"
    ref = "heads/#{branch}"

    begin
      # First grab the files in this branch
      files = github_client.contents(papers_repo,
                                     :path => branch,
                                     :ref => ref)

      files.each do |file|
        github_client.delete_contents(papers_repo,
                                      file.path,
                                      "Deleting #{file.name}",
                                      file.sha,
                                      :branch => branch)
      end

      # Delete the old branch
      github_client.delete_ref(papers_repo, "heads/#{journal_alias}.#{id}")

      # Then create it again
      github_client.create_ref(papers_repo, "heads/#{journal_alias}.#{id}", get_master_ref(papers_repo))
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
    puts `cat #{file_path}`
    gh_response = github_client.create_contents(papers_repo,
                                                pdf_path,
                                                "Creating 10.21105.#{journal_alias}.#{id}.pdf",
                                                File.open("#{file_path.strip}").read,
                                                :branch => "#{journal_alias}.#{id}")

    return gh_response.content.html_url
  end

  # Use the GitHub Contents API (https://developer.github.com/v3/repos/contents/)
  # to write the compiled PDF to a named branch.
  # Returns the URL to the PDF on GitHub
  def create_git_xml(file_path, issue_id, papers_repo, journal_alias)
    id = "%05d" % issue_id
    crossref_xml_path = "#{journal_alias}.#{id}/10.21105.#{journal_alias}.#{id}.crossref.xml"

    puts "FILE PATH IS #{file_path}"
    puts `cat #{file_path}`
    gh_response = github_client.create_contents(papers_repo,
                                                crossref_xml_path,
                                                "Creating 10.21105.#{journal_alias}.#{id}.crossref.xml",
                                                File.open("#{file_path.strip}").read,
                                                :branch => "#{journal_alias}.#{id}")

    return gh_response.content.html_url
  end

  def create_deposit_pr(issue_id, papers_repo, journal_alias, dry_run)
    id = "%05d" % issue_id

    gh_response = github_client.create_pull_request(papers_repo, "master", "#{journal_alias}.#{id}",
  "Creating pull request for 10.21105.#{journal_alias}.#{id}", "If this looks good then :shipit:")

    # Merge it!
    if dry_run == false
      #GitHub needs us to slow down sometimes: "Base branch was modified. Review and try the merge again."
      sleep(5)
      github_client.merge_pull_request(papers_repo, gh_response.number, 'Merging by @whedon bot')
    end

    return gh_response.html_url
  end
end
