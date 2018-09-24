class FakeJoss < Sinatra::Base
  # Assignees
  post '/papers/api_start_review' do
    json_response 201, 'joss-paper.json'
  end

  private

  def json_response(response_code, file_name)
    content_type :json
    status response_code
    File.open(File.dirname(__FILE__) + '/fixtures/' + file_name, 'rb').read
  end
end
