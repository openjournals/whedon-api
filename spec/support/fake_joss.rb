class FakeJoss < Sinatra::Base
  # Assignees
  post '/papers/api_start_review' do
    json_response 201, 'joss-paper.json'
  end

  # Reject paper
  post '/papers/api_reject' do
    status 204
  end

  # Withdraw paper
  post '/papers/api_withdraw' do
    status 204
  end

  private

  def json_response(response_code, file_name)
    content_type :json
    status response_code
    File.open(File.dirname(__FILE__) + '/fixtures/' + file_name, 'rb').read
  end
end
