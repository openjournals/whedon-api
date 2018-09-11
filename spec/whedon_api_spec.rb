require File.expand_path '../spec_helper.rb', __FILE__

describe WhedonApi do
  subject do
    app = described_class.new!
  end

  let(:pre_review_created_payload) { json_fixture('pre-review-created-with-editor.json') }
  let(:wrong_repo_payload) { json_fixture('pre-review-created-with-editor-for-wrong-repo.json') }
  let(:junk_payload) { json_fixture('junk-payload.json') }

  it "should halt for junk incoming JSON" do
    post '/dispatch', junk_payload, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_unprocessable
    # expect(assigns(:action)).to be_nil TODO: Figure out if something like this is possible.
  end

  it "should halt for a payload coming from the wrong review repo" do
    post '/dispatch', wrong_repo_payload, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response).to be_unprocessable
  end

  it "should say hello for valid payload" do
    post '/dispatch', pre_review_created_payload, {'CONTENT_TYPE' => 'application/json'}
    expect(subject.journal_configs_initialized?).to be_truthy
  end
end
