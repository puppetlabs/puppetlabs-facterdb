# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::ReleaseNotes do
  let(:fixture) { File.read(File.expand_path('../../../fixtures/release_notes/release_notes_facter.html', __dir__)) }
  let(:notes) { described_class.parse(fixture) }

  describe '.parse' do
    {
      '4.23.0' => { '9' => '9.1.3', '8' => '8.22.2' },
      '4.22.0' => { '9' => '9.1.0', '8' => '8.22.0' },
      '4.21.0' => { '9' => '9.0.0', '8' => '8.21.0' },
      '4.20.0' => { '8' => '8.20.0' },
      '4.14.0' => { '8' => '8.14.0' },
      '4.12.0' => { '8' => '8.12.0' },
    }.each do |version, agents|
      it "maps #{version} to #{agents}" do
        expect(notes.agents_for(version)).to eq(agents)
      end
    end

    it 'parses the "4.14. 0" heading quirk as 4.14.0' do
      expect(notes.versions).to include('4.14.0')
    end

    it 'ignores pre-Core entries that name only Puppet' do
      expect(notes.core_versions('4.11.0')).to eq([])
    end

    it 'returns no core versions for unknown versions' do
      expect(notes.core_versions('9.9.9')).to eq([])
    end

    it 'returns no agents for unknown versions' do
      expect(notes.agents_for('9.9.9')).to eq({})
    end

    it 'parses wording variants from inline HTML' do
      html = '<h2>Facter 4.30.0</h2><p>Released December 2026 and shipped with Puppet Core 9.2.0.</p>'
      expect(described_class.parse(html).agents_for('4.30.0')).to eq('9' => '9.2.0')
    end

    it 'keeps the highest agent within a major' do
      html = '<h2>Facter 4.30.0</h2><p>Released with Puppet Core 8.22.0, 8.22.2 and 9.1.0.</p>'
      expect(described_class.parse(html).agents_for('4.30.0')).to eq('8' => '8.22.2', '9' => '9.1.0')
    end
  end

  describe '.fetch' do
    it 'rejects a non-https URL' do
      expect { described_class.fetch('http://help.puppet.com/x.htm') }.to raise_error(ArgumentError)
    end

    it 'raises on a non-200 response' do
      response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
      allow(Net::HTTP).to receive(:start).and_return(response)
      expect { described_class.fetch }.to raise_error(%r{404})
    end

    it 'parses a 200 response body' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('<h2>Facter 4.30.0</h2><p>with Puppet Core 9.2.0.</p>')
      allow(Net::HTTP).to receive(:start).and_return(response)
      expect(described_class.fetch.agents_for('4.30.0')).to eq('9' => '9.2.0')
    end

    it 'refuses redirects to other hosts' do
      response = Net::HTTPFound.new('1.1', '302', 'Found')
      response['location'] = 'https://evil.example.com/x'
      allow(Net::HTTP).to receive(:start).and_return(response)
      expect { described_class.fetch }.to raise_error(ArgumentError, %r{redirect})
    end
  end
end
