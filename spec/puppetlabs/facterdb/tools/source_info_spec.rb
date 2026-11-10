# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::SourceInfo do
  let(:info) { described_class.new(Puppetlabs::FacterDB::Tools::REPO_ROOT) }

  it 'reports the commit and dirty flag for a git checkout' do
    expect(info.to_h).to include('commit' => %r{\A\h{40}\z}, 'dirty' => be(true).or(be(false)))
  end

  it 'raises when git status cannot be read' do
    allow(info).to receive(:git).and_call_original
    allow(info).to receive(:git).with('status', '--porcelain').and_return(nil)
    expect { info.to_h }.to raise_error(ArgumentError, %r{git status})
  end
end
