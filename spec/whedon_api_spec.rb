require File.expand_path '../spec_helper.rb', __FILE__

describe WhedonApi do
  let(:pre_review_created_payload) { json_fixture('pre-review-created-with-editor.json') }
  let(:wrong_repo_payload) { json_fixture('pre-review-created-with-editor-for-wrong-repo.json') }
  let(:junk_payload) { json_fixture('junk-payload.json') }
  let(:pre_review_closed_payload) { json_fixture('pre-review-issue-closed-936.json') }
  let(:review_closed_payload) { json_fixture('review-issue-closed-937.json') }

  subject do
    app = described_class.new!
  end

  context 'with junk params' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).never
      post '/dispatch', junk_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should halt" do
      expect(last_response).to be_unprocessable
    end
  end

  context 'with a payload from an unknown repository' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).never
      post '/dispatch', wrong_repo_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should halt" do
      expect(last_response).to be_unprocessable
    end
  end

  context 'with a payload from an known repository' do
    before do
      expect(PDFWorker).to receive(:perform_async).once
      expect(RepoWorker).to receive(:perform_async).once
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).twice
      post '/dispatch', pre_review_created_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(subject.journal_configs_initialized?).to be_truthy
    end

    it "should say hello" do
      expect(last_response).to be_ok
    end
  end

  context 'when closing a REVIEW issue' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once
      post '/dispatch', review_closed_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  context 'when closing a PRE-REVIEW issue' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).never
      post '/dispatch', pre_review_closed_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end
end
