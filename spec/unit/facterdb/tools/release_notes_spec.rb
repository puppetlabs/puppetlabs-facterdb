# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::ReleaseNotes, :aggregate_failures do
  let(:fixture) { File.read(File.expand_path('../../../fixtures/release_notes/release_notes_facter.html', __dir__)) }
  let(:versions) { described_class.parse(fixture) }

  it 'pairs Facter versions with the newest Puppet Core agent' do
    expect(versions).to include('4.23.0' => '9.1.3', '4.22.0' => '9.1.0', '4.21.0' => '9.0.0', '4.20.0' => '8.20.0', '4.12.0' => '8.12.0')
  end

  it 'includes 4.14.0 despite the split heading' do
    expect(versions).to have_key('4.14.0')
  end

  it 'gives every version from 4.12.0 an X.Y.Z agent of major 8 or 9' do
    floor = Gem::Version.new('4.12.0')
    recent = versions.select { |v, _| Gem::Version.new(v) >= floor }
    expect(recent).not_to be_empty
    recent.each_value { |agent| expect(agent).to match(%r{\A(8|9)\.\d+\.\d+\z}) }
  end

  it 'takes the newest agent when two are listed' do
    html = '<h2>Facter 4.30.0</h2><p>Released May 2027 with Puppet Core 8.30.0 and 9.5.0.</p>'
    expect(described_class.parse(html)).to eq('4.30.0' => '9.5.0')
  end

  it 'omits a version without a Puppet Core clause and raises MissingVersion' do
    notes = described_class.new('<h2>Facter 4.30.0</h2><p>Released May 2027.</p>')
    expect(notes.versions).not_to have_key('4.30.0')
    expect { notes.agent_for!('4.30.0') }.to raise_error(described_class::MissingVersion, %r{4\.30\.0})
  end

  it 'does not let a table of contents entry override a real section' do
    html = '<ul><li>Facter 4.30.0</li><li>Facter 4.29.0</li></ul><h2>Facter 4.30.0</h2><p>Shipped with Puppet Core 9.5.0.</p>'
    expect(described_class.parse(html)).to eq('4.30.0' => '9.5.0')
  end
end
