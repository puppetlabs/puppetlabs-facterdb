# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe 'config/platforms.yml' do # rubocop:disable RSpec/DescribeClass
  let(:platforms) { Puppetlabs::FacterDB::Tools::Platforms.load }

  it 'has a valid schema' do
    expect(platforms.errors).to eq([])
  end

  it 'covers every Puppet Core supported triple with an entry or a skip reason' do
    expect(platforms.coverage_gaps).to eq([])
  end

  it 'gives every skip entry a non-empty reason' do
    expect(platforms.skipped.map(&:skip)).to all(be_a(String).and(satisfy { |reason| !reason.strip.empty? }))
  end

  it 'pins every runner label' do
    expect(platforms.active.map(&:runner)).not_to include(match(%r{-latest}))
  end

  it 'avoids latest tags on container images' do
    images = platforms.active.select { |e| e.backend == 'container' }.map(&:image)
    expect(images).to all(satisfy { |image| image.include?(':') && !image.end_with?(':latest') })
  end

  it 'uses ids that are valid fact filenames' do
    invalid = platforms.active.map(&:filename).reject { |name| Puppetlabs::FacterDB::Tools::Validator.filename_valid?(name, []) }
    expect(invalid).to eq([])
  end
end
