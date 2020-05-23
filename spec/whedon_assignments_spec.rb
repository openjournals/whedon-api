require File.expand_path '../spec_helper.rb', __FILE__

describe WhedonApi do
  let(:whedon_commands_from_editor) { json_fixture('whedon-commands-editor-on-pre-review-issue-936.json') }
  let(:whedon_commands_from_non_editor) { json_fixture('whedon-commands-non-editor-on-pre-review-issue-936.json') }
  let(:whedon_assign_editor_from_editor) { json_fixture('whedon-assign-editor-on-pre-review-issue-936.json') }
  let(:whedon_assign_me_as_editor_from_editor) { json_fixture('whedon-assign-me-as-editor-on-pre-review-issue-936.json') }
  let(:whedon_assign_editor_from_non_editor) { json_fixture('whedon-assign-editor-non-editor-on-pre-review-issue-936.json') }
  let(:whedon_assign_reviewer_from_editor) { json_fixture('whedon-assign-reviewer-on-pre-review-issue-936.json') }
  let(:whedon_assign_reviewer_from_non_editor) { json_fixture('whedon-assign-reviewer-non-editor-on-pre-review-issue-936.json') }
  let(:whedon_commands_from_editor_response) { erb_response('commands.erb')}
  let(:whedon_commands_from_non_editor_response) { erb_response('commands_public.erb')}

  subject do
    app = described_class.allocate
    app.send :initialize
    app
  end

  context 'with @whedon commands as editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, whedon_commands_from_editor_response)
      post '/dispatch', whedon_commands_from_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be OK" do
      expect(last_response).to be_ok
    end
  end

  context 'with @whedon commands as non-editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, whedon_commands_from_non_editor_response)
      post '/dispatch', whedon_commands_from_non_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be OK" do
      expect(last_response).to be_ok
    end
  end

  context 'with @whedon assign @arfon as editor as non-editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm afraid I can't do that. That's something only editors are allowed to do./)
      expect_any_instance_of(WhedonApi).to receive(:assign_editor).never
      post '/dispatch', whedon_assign_editor_from_non_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be forbidden" do
      expect(last_response).to be_forbidden
    end
  end

  context 'with @whedon assign @arfon as editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /OK, the editor is @arfon/)
      expect_any_instance_of(WhedonApi).to receive(:assign_editor).once.with('@arfon').and_return('arfon')
      post '/dispatch', whedon_assign_editor_from_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be OK" do
      expect(last_response).to be_ok
    end
  end

  context 'with @whedon assign me as editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /OK, the editor is @arfon/)
      expect_any_instance_of(WhedonApi).to receive(:assign_editor).once.with('me').and_return('arfon')
      post '/dispatch', whedon_assign_me_as_editor_from_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be OK" do
      expect(last_response).to be_ok
    end
  end

  context 'assign editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:update_issue).and_return(true)
      expect_any_instance_of(WhedonApi).to receive(:issue).twice.and_return(OpenStruct.new(body: "", title: ""))
      expect_any_instance_of(WhedonApi).to receive(:reviewers).and_return([])
      expect_any_instance_of(WhedonApi).to receive(:update_assignees).and_return(true)
      expect(RestClient).to receive(:post).and_return(true)
      subject.instance_variable_set(:@config, OpenStruct.new(site_host: "", site_api_key: ""))
      subject.instance_variable_set(:@issue_id, 33)
      subject.instance_variable_set(:@sender, "arfon")
    end

    it "should return new editor" do
      expect(subject.assign_editor('@new_editor')).to eq('new_editor')
    end

    it "should return sender if called using 'me'" do
      expect(subject.assign_editor('me')).to eq('arfon')
    end
  end

  context 'with @whedon assign @reviewer reviewer as non-editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm afraid I can't do that. That's something only editors are allowed to do./)
      expect_any_instance_of(WhedonApi).to receive(:assign_reviewer).never
      post '/dispatch', whedon_assign_reviewer_from_non_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be forbidden" do
      expect(last_response).to be_forbidden
    end
  end

  context 'with @whedon assign @reviewer reviewer as editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect_any_instance_of(WhedonApi).to receive(:assign_reviewer).once.with('@reviewer')
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /OK, @reviewer is now a reviewer/)
      post '/dispatch', whedon_assign_reviewer_from_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be OK" do
      expect(last_response).to be_ok
    end
  end

  # To test:
  # - Add reviewer (as editor)
  # - Add reviewer (as non-editor)
  # - Remove reviewer (as editor)
  # - Remove editor (as editor)
  # - Remove reviewer (as non-editor)
  # - Remove editor (as non-editor)
end
