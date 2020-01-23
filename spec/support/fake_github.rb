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

  # Pre-review issue with editor and reviewer assigned
  get '/repos/openjournals/joss-reviews-testing/issues/935' do
    json_response 200, 'pre-review-issue-935.json'
  end

  # Closing pre-review issue once review has been started.
  patch '/repos/openjournals/joss-reviews-testing/issues/935' do
    json_response 200, 'pre-review-issue-935.json'
  end

  # Review issue
  get '/repos/openjournals/joss-reviews-testing/issues/937' do
    json_response 200, 'review-issue-937.json'
  end

  post '/repos/openjournals/joss-reviews-testing/issues/937/comments' do
    json_response 201, 'pre-review-issue-comment-created-937.json'
  end

  # Review issue with multiple reviewers
  get '/repos/openjournals/joss-reviews-testing/issues/1203' do
    json_response 200, 'review-issue-1203.json'
  end

  # Review issue (with archive DOI set)
  get '/repos/openjournals/joss-reviews-testing/issues/938' do
    json_response 200, 'review-issue-938.json'
  end

  post '/repos/openjournals/joss-reviews-testing/issues/938/labels' do
    json_response 200, 'review-issue-938-labels.json'
  end

  post '/repos/openjournals/joss-reviews-testing/issues/936/labels' do
    json_response 200, 'review-issue-936-labels.json'
  end

  post '/repos/openjournals/joss-reviews-testing/issues/938/comments' do
    json_response 201, 'comment-created-938.json'
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
