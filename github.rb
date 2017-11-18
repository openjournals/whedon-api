module GitHub
  # Authenticated Octokit
  # TODO remove license preview media type when this ships
  MEDIA_TYPE = "application/vnd.github.drax-preview+json"

  def github_client
    @github_client ||= Octokit::Client.new( :access_token => ENV['GH_TOKEN'],
                                            :default_media_type => MEDIA_TYPE)
  end
end
