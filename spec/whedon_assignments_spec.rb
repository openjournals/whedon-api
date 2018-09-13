require File.expand_path '../spec_helper.rb', __FILE__

describe WhedonApi do
  let(:whedon_commands_from_editor) { json_fixture('whedon-commands-editor-on-pre-review-issue-936.json') }
  let(:whedon_commands_from_non_editor) { json_fixture('whedon-commands-non-editor-on-pre-review-issue-936.json') }
  let(:whedon_assign_editor_from_editor) { json_fixture('whedon-assign-editor-on-pre-review-issue-936.json') }
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
      expect_any_instance_of(WhedonApi).to receive(:assign_editor).once.with('@arfon')
      post '/dispatch', whedon_assign_editor_from_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be OK" do
      expect(last_response).to be_ok
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
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /OK, the reviewer is @reviewer/)
      post '/dispatch', whedon_assign_reviewer_from_editor, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should be OK" do
      expect(last_response).to be_ok
    end
  end
end
