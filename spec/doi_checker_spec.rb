require File.expand_path '../spec_helper.rb', __FILE__
require 'sidekiq/testing'

describe DOIWorker do
  let(:bibtex) { fixture('paper.bib') }

  before(:each) do
    Sidekiq::Worker.clear_all
  end

  subject do
    described_class.new
  end

  context "instance methods" do
    it "should know how to check DOIs" do
      expect(subject.check_dois(bibtex)).to eq(
          {
            :invalid =>["http://doi.org/10.1038/INVALID is INVALID", "http://doi.org/http://notadoi.org/bioinformatics/btp450 is INVALID"],
            :missing=>[],
            :ok=>["http://doi.org/10.1038/nmeth.3252 is OK"]
            }
          )
    end
  end
end
