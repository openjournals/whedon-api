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

  def needs_reminder?(nwo, issue_body, human)
    reviewers = issue_body.match(/Reviewers?:\*\*\s*(.+?)\r?\n/)[1].split(", ") - ["Pending"]

    # Return false if the human isn't one of the reviewers
    return false unless reviewers.include?(human)

    # Check if there are any unchecked review boxes
    # TODO: work out how to do this for each reviewer separately
    return outstanding_review_for?(issue_body, reviewers, human)
  end

  # TODO figure out how to fix this mess.
  # Takes an issue body and a GitHub handle and determines if
  # the author has any checkboxes unchecked.
  def outstanding_review_for?(issue_body, reviewers, human)
    # If there's only one reviewer then we just need to check if there
    # are any unchecked checkboxes, returning false if there are.
    if reviewers.count == 1
      if outstanding_checkboxes?(issue_body)
        return true
      else
        return false
      end

    # If there's more than one reviewer then we need to try and grab
    # the checklist for their section of the issue body. It's easiest
    # to check if they're the last first and work back from there.
    else
      # if this is true then they are the last checklist in the review
      # issue which means we can just match everything to the end.
      if issue_body[/(?<=Review checklist for #{human}).*(Review checklist for)/m].nil?
        checklist = issue_body[/(?<=Review checklist for #{human}).*/m]

        if outstanding_checkboxes?(checklist)
          return true
        else
          return false
        end
      # Finally, in this case, we have a reviewer checklist that is
      # in the middle of the review issue body so we scan for their
      # checklist and stop when we detect the start of the next one
      else
        checklist = issue_body[/(?<=Review checklist for #{human}).*(Review checklist for)/m]
        if outstanding_checkboxes?(checklist)
          return true
        else
          return false
        end
      end
    end
  end

  # Take a section of a review issue (presumably with a checklist) and see
  # if there are unchecked checkboxes.
  def outstanding_checkboxes?(checklist)
    checkbox_count = checklist.scan(/(- \[ \]|- \[x\])/m).count
    checked_checkbox_count = checklist.scan(/(- \[x\])/m).count
    if checkbox_count > checked_checkbox_count
      return true
    else
      return false
    end
  end

  def label_issue(nwo, issue_id, languages)
    github_client.add_labels_to_an_issue(nwo, issue_id, languages)
  end

  def close_issue(nwo, issue_id)
    github_client.close_issue(nwo, issue_id)
  end

  # Get the SHA for the last commit in the master branch of the papers repo
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
    rescue Octokit::NotFound # If the branch doesn't exist, or there aren't any commits in the branch then create it!
      begin
        github_client.create_ref(papers_repo, "heads/#{journal_alias}.#{id}", get_master_ref(papers_repo))
      rescue Octokit::UnprocessableEntity
        # If the branch already exists move on...
      end
    end
  end

  # Use the GitHub Contents API (https://developer.github.com/v3/repos/contents/)
  # to write the compiled PDF to a named branch.
  # Returns the URL to the PDF on GitHub
  def create_git_pdf(file_path, issue_id, papers_repo, journal_alias)
    id = "%05d" % issue_id
    pdf_path = "#{journal_alias}.#{id}/10.21105.#{journal_alias}.#{id}.pdf"
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
      #GitHub needs us to slow down sometimes: "Base branch was modified.
      # Review and try the merge again."
      sleep(5)
      github_client.merge_pull_request(papers_repo, gh_response.number, 'Merging by @whedon bot')

      # Next delete the branch that we've just merged
      github_client.delete_ref(papers_repo, "heads/#{journal_alias}.#{id}")
    end

    return gh_response.html_url
  end
end
