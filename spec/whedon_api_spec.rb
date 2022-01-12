require File.expand_path '../spec_helper.rb', __FILE__

describe WhedonApi do
  let(:pre_review_created_payload) { json_fixture('pre-review-created-with-editor.json') }
  let(:review_created_payload) { json_fixture('review-created-with-editor.json') }
  let(:wrong_repo_payload) { json_fixture('pre-review-created-with-editor-for-wrong-repo.json') }
  let(:junk_payload) { json_fixture('junk-payload.json') }
  let(:issue_created_payload) { json_fixture('issue-created.json') }
  let(:pre_review_closed_payload) { json_fixture('pre-review-issue-closed-936.json') }
  let(:review_closed_payload) { json_fixture('review-issue-closed-937.json') }
  let(:whedon_start_review_from_editor_not_ready) { json_fixture('whedon-start-review-editor-on-pre-review-issue-936.json') }
  let(:whedon_start_review_on_review_issue) { json_fixture('whedon-start-review-on-review-issue-937.json') }
  let(:whedon_start_review_from_editor_ready) { json_fixture('whedon-start-review-editor-on-pre-review-issue-935.json') }
  let(:whedon_start_review_from_non_editor_ready) { json_fixture('whedon-start-review-non-editor-on-pre-review-issue-935.json') }
  let(:whedon_generate_pdf) { json_fixture('whedon-generate-pdf-936.json') }
  let(:whedon_reject) { json_fixture('whedon-reject-936.json') }
  let(:whedon_reject_non_eic) { json_fixture('whedon-reject-non-eic-936.json') }
  let(:whedon_withdraw) { json_fixture('whedon-withdraw-936.json') }
  let(:whedon_withdraw_non_eic) { json_fixture('whedon-withdraw-non-eic-936.json') }
  let(:whedon_invite) { json_fixture('whedon-invite-936.json') }
  let(:whedon_invite_non_eic) { json_fixture('whedon-invite-non-eic-936.json') }
  let(:whedon_nonsense) { json_fixture('whedon-nonsense-936.json') }
  let(:whedon_really_nonsense) { json_fixture('whedon-really-nonsense-936.json') }
  let(:whedon_accept_no_doi) { json_fixture('whedon-accept-no-doi-on-review-issue-937.json')}
  let(:whedon_accept_with_doi) { json_fixture('whedon-accept-with-doi-on-review-issue-938.json')}
  let(:whedon_accept_for_reals_with_doi) { json_fixture('whedon-accept-for-reals-with-doi-on-review-issue-938.json')}
  let(:whedon_accept_non_eic_for_reals_with_doi
) { json_fixture('whedon-accept-non-eic-for-reals-with-doi-on-review-issue-938.json')}
  let(:whedon_set_reminder_for_non_reviewer_on_pre_review) { json_fixture('whedon-seting-reminder-for-non-reviewer-on-pre-review.json')}
  let(:whedon_set_reminder_for_author_on_pre_review) { json_fixture('whedon-seting-reminder-for-author-on-pre-review.json')}
  let(:whedon_set_reminder_for_author_on_review_string_units) { json_fixture('whedon-seting-reminder-for-author-on-review-string-units.json')}
  let(:whedon_set_reminder_for_author_on_review_good_units) { json_fixture('whedon-seting-reminder-for-author-on-review-good-units.json')}
  let(:whedon_set_reminder_for_author_on_review_bonkers_units) { json_fixture('whedon-seting-reminder-for-author-on-review-bonkers-units.json')}

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

  xcontext 'when starting a PRE-REVIEW issue with a payload from an known repository' do
    before do
      expect(PDFWorker).to receive(:perform_async).once
      expect(RepoWorker).to receive(:perform_async).once
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).exactly(1).times
      post '/dispatch', pre_review_created_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(subject.journal_configs_initialized?).to be_truthy
    end

    it "should say hello" do
      expect(last_response).to be_ok
    end
  end

  xcontext "when opening an issue that isn't a PRE-REVIEW or REVIEW issue" do
    before do
      expect(PDFWorker).to receive(:perform_async).never
      expect(RepoWorker).to receive(:perform_async).never
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with("openjournals/joss-reviews-testing", 940, /This repository is only for review issues/)
      post '/dispatch', issue_created_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "close the issue" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when starting a REVIEW issue with a payload from an known repository' do
    before do
      expect(PDFWorker).to receive(:perform_async).once
      expect(RepoWorker).to receive(:perform_async).once
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).exactly(1).times
      post '/dispatch', review_created_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(subject.journal_configs_initialized?).to be_truthy
    end

    it "should say hello" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when closing a REVIEW issue' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once
      post '/dispatch', review_closed_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when closing a PRE-REVIEW issue' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).never
      post '/dispatch', pre_review_closed_payload, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when rejecting a paper as a regular user' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm sorry/)
      post '/dispatch', whedon_reject_non_eic, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_forbidden
    end
  end

  xcontext 'when rejecting a paper as an EIC' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /Paper rejected/)
      post '/dispatch', whedon_reject, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when withdrawing a paper as a regular user' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm sorry/)
      post '/dispatch', whedon_withdraw_non_eic, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_forbidden
    end
  end

  xcontext 'when withdrawing a paper as an EIC' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /Paper withdrawn/)
      post '/dispatch', whedon_withdraw, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when inviting an editor as a regular user' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm sorry/)
      post '/dispatch', whedon_invite_non_eic, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_forbidden
    end
  end

  xcontext 'when inviting an editor as an EiC' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /@mickey has been invited to edit this submission/)
      post '/dispatch', whedon_invite, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when starting review WITHOUT reviewer and editor assignments' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /It looks like you don't have an editor and reviewer assigned yet so I can't start the review./)
      post '/dispatch', whedon_start_review_from_editor_not_ready, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when starting review on a REVIEW issue' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /Can't start a review when the review has already started/)
      post '/dispatch', whedon_start_review_on_review_issue, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_unprocessable
    end
  end

  xcontext 'when starting review WITH reviewer and editor assignments as editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /OK, I've started the review over in https:\/\/github.com\/openjournals\/joss-reviews-testing\/issues\/1234./)
      post '/dispatch', whedon_start_review_from_editor_ready, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when starting review WITH reviewer and editor assignments as non editor' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm sorry @barfon, I'm afraid I can't do that. That's something only editors are allowed to do./)
      post '/dispatch', whedon_start_review_from_non_editor_ready, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_forbidden
    end
  end

  xcontext 'when accepting a paper as an editor without an archive DOI' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /No archive DOI set. Exiting.../)
      post '/dispatch', whedon_accept_no_doi, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when accepting a paper as an editor with an archive DOI' do
    before do
      expect(DepositWorker).to receive(:perform_async).once
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /Attempting dry run of processing paper acceptance/)
      expect(github_client).to receive(:label_issue).never
      post '/dispatch', whedon_accept_with_doi, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when accepting a paper (for reals) as an (EiC) editor with an archive DOI' do
    before do
      expect(DepositWorker).to receive(:perform_async).once
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /Doing it live! Attempting automated processing of paper acceptance.../)
      post '/dispatch', whedon_accept_for_reals_with_doi, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when accepting a paper (for reals) as an editor with an archive DOI' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm sorry @barf, I'm afraid I can't do that. That's something only editor-in-chiefs are allowed to do./)
      post '/dispatch', whedon_accept_non_eic_for_reals_with_doi, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_forbidden
    end
  end

  xcontext 'when generating a pdf' do
    before do
      expect(PDFWorker).to receive(:perform_async).once
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /Attempting PDF compilation from custom branch custom-branch-name. Reticulating splines etc.../)
      post '/dispatch', whedon_generate_pdf, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  context 'when @whedon is addressed' do
    before do
      expect(PDFWorker).to_not receive(:perform_async)
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)

      expected_response = "I have been decommissioned, my succesor @editorialbot will help you. \n\nPlease use `@editorialbot help` to list available options."
      expect(github_client).to receive(:add_comment).once.with(anything, anything, expected_response)
      post '/dispatch', whedon_generate_pdf, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should reply it has been decommissioned" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when @whedon is addressed speaking nonsense' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with(anything, anything, /I'm sorry human, I don't understand that/)
      post '/dispatch', whedon_nonsense, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext 'when @whedon is NOT addressed speaking nonsense' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).never
      post '/dispatch', whedon_really_nonsense, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext '[PRE-REVIEW] when setting a reminder for someone who is not a reviewer or author' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with("openjournals/joss-reviews-testing", 936, "Sorry, I can't set reminders on PRE-REVIEW issues.")

      post '/dispatch', whedon_set_reminder_for_non_reviewer_on_pre_review, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end

    it "should not schedule a reminder" do
      expect(ReviewReminderWorker).to receive(:perform_async).never
    end
  end

  xcontext '[PRE-REVIEW] when setting a reminder for an author' do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with("openjournals/joss-reviews-testing", 936, "Sorry, I can't set reminders on PRE-REVIEW issues.")

      post '/dispatch', whedon_set_reminder_for_author_on_pre_review, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end

    it "should not schedule a reminder" do
      expect(ReviewReminderWorker).to receive(:perform_async).never
    end
  end

  xcontext "[REVIEW] when setting a reminder for an author with string units" do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with("openjournals/joss-reviews-testing", 937, "Reminder set for @mpascariu in two weeks")

      post '/dispatch', whedon_set_reminder_for_author_on_review_string_units, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end
  end

  xcontext "[REVIEW] when setting a reminder for an author with integer units" do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      expect(github_client).to receive(:add_comment).once.with("openjournals/joss-reviews-testing", 937, "Reminder set for @mpascariu in 2 weeks")
      expect(ReviewReminderWorker).to receive(:perform_at).once

      post '/dispatch', whedon_set_reminder_for_author_on_review_good_units, {'CONTENT_TYPE' => 'application/json'}
    end

    it "should initialize properly" do
      expect(last_response).to be_ok
    end

    context "time conversions" do
      it "should be able to convert 'days' to seconds" do
        expect(subject.target_time(3, 'days').to_f).to be_within(30).of((Time.now + (3 * 86400)).to_f)
      end

      it "should be able to convert 'day' to seconds" do
        expect(subject.target_time(3, 'day').to_f).to be_within(30).of((Time.now + (3 * 86400)).to_f)
      end

      it "should be able to convert 'week' to seconds" do
        expect(subject.target_time(1, 'week').to_f).to be_within(30).of((Time.now + (7 * 86400)).to_f)
      end

      it "should be able to convert 'week' to seconds" do
        expect(subject.target_time(10, 'weeks').to_f).to be_within(30).of((Time.now + (70 * 86400)).to_f)
      end
    end

    context "[REVIEW] when setting a reminder for an author with a bonkers time" do
      before do
        allow(Octokit::Client).to receive(:new).once.and_return(github_client)
        expect(github_client).to receive(:add_comment).once.with("openjournals/joss-reviews-testing", 937, "I don't recognize this description of time 'pink' 'flamingo'.")

        post '/dispatch', whedon_set_reminder_for_author_on_review_bonkers_units, {'CONTENT_TYPE' => 'application/json'}
      end

      it "should initialize properly" do
        expect(last_response).to be_ok
      end
      #
      # it "should not schedule a reminder" do
      #   expect(ReviewReminderWorker).to receive(:perform_async).never
      # end
    end


    # context "validating times" do
    #   before do
    #     allow(Octokit::Client).to receive(:new).once.and_return(github_client)
    #   end
    #
    #   it "should know what to do with non-numerical units" do
    #     expect(github_client).to receive(:add_comment).once.with(anything, anything, "I don't know what to do with 'three days'. Please specific a numerical unit.")
    #   end
    # end
  end
end
