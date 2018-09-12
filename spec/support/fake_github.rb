class FakeGitHub < Sinatra::Base
  get '/teams/:id/members' do
    json_response 200, 'team.json'
  end

  # Pre-review issue
  get '/repos/openjournals/joss-reviews-testing/issues/936' do
    json_response 200, 'pre-review-issue-936.json'
  end

  post '/repos/openjournals/joss-reviews-testing/issues/936/comments' do
    json_response 201, 'pre-review-issue-comment-created-936.json'
  end

  patch '/repos/openjournals/joss-reviews-testing/issues/936' do
    json_response 200, 'pre-review-issue-comment-updated-936.json'
  end

  # Review issue
  get '/repos/openjournals/joss-reviews-testing/issues/937' do
    json_response 200, 'review-issue-937.json'
  end

  post '/repos/openjournals/joss-reviews-testing/issues/937/comments' do
    json_response 201, 'pre-review-issue-comment-created-937.json'
  end

  # Assignees
  post '/repos/openjournals/joss-reviews-testing/issues/936/assignees' do
    json_response 201, 'updated-assignees-pre-review-issue-936.json'
  end

  private

  def json_response(response_code, file_name)
    content_type :json
    status response_code
    File.open(File.dirname(__FILE__) + '/fixtures/' + file_name, 'rb').read
  end
end
