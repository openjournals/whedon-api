require File.expand_path '../spec_helper.rb', __FILE__

describe GitHub do
  let(:review_issue_with_single_reviewer) { json_fixture('review-issue-938.json') }
  let(:review_issue_with_multiple_reviewers) { json_fixture('review-issue-1203.json') }

  subject do
    described_class
  end

  context "for a single reviewer" do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      @body = JSON.parse(review_issue_with_single_reviewer)['body']
    end

    it "should know that a reviewer not involved with the review doesn't need a reminder" do
      expect(subject.needs_reminder?('openjournals/joss-reviews-testing', @body, '@human')).to be_falsey
    end

    it "should know that a reviewer involved with a review does need a reminder" do
      expect(subject.needs_reminder?('openjournals/joss-reviews-testing', @body, '@rlbarter')).to be_truthy
    end
  end

  context "for multiple reviewers" do
    before do
      allow(Octokit::Client).to receive(:new).once.and_return(github_client)
      @body = JSON.parse(review_issue_with_multiple_reviewers)['body']
    end

    it "should know that a reviewer not involved with the review doesn't need a reminder" do
      expect(subject.needs_reminder?('openjournals/joss-reviews-testing', @body, '@human')).to be_falsey
    end

    it "should know that a reviewer involved with a review does need a reminder" do
      expect(subject.needs_reminder?('openjournals/joss-reviews-testing', @body, '@stuartcampbell')).to be_truthy
    end

    it "should know how to handle a reviewer listed at the top of the review issue" do
      body = JSON.parse(review_issue_with_multiple_reviewers)['body']
      expect(subject.outstanding_review_for?(body, ['@myousefi2016', '@stuartcampbell', '@mdoucet'], '@myousefi2016')).to be_truthy
    end

    it "should know how to handle a reviewer listed in the middle of the review issue" do
      body = JSON.parse(review_issue_with_multiple_reviewers)['body']
      expect(subject.outstanding_review_for?(body, ['@myousefi2016', '@stuartcampbell', '@mdoucet'], '@stuartcampbell')).to be_truthy
    end

    it "should know how to handle a reviewer listed in the bottom of the review issue" do
      body = JSON.parse(review_issue_with_multiple_reviewers)['body']
      expect(subject.outstanding_review_for?(body, ['@myousefi2016', '@stuartcampbell', '@mdoucet'], '@mdoucet')).to be_falsey
    end
  end
end
