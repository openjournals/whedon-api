require 'octokit'

module GitHub
  # Authenticated Octokit

  def github_client
    @github_client ||= Octokit::Client.new( :access_token => ENV['GH_TOKEN'],
                                            :auto_paginate => true)
  end
end
