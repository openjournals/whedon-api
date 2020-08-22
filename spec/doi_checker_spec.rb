require File.expand_path '../spec_helper.rb', __FILE__
require 'sidekiq/testing'

describe DOIWorker do
  let(:entries) { BibTeX.open(fixture('paper.bib'), :filter => :latex) }

  before(:each) do
    Sidekiq::Worker.clear_all
  end

  subject do
    described_class.new
  end

  context "instance methods" do
    it "should know how to check DOIs" do
      expect(subject.check_dois(entries)).to eq(
          {
            :invalid =>["10.1038/INVALID is INVALID", "http://notadoi.org/bioinformatics/btp450 is INVALID because of 'https://doi.org/' prefix"],
            :missing=>[],
            :ok=>["10.1038/nmeth.3252 is OK"]
            }
          )
    end
  end
end
