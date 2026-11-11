# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::CoreIndex, :aggregate_failures do
  let(:body) { File.read(File.expand_path('../../../fixtures/core_index/facter', __dir__)) }

  describe '.parse' do
    it 'returns ascending unique release versions without platform variants or prereleases' do
      expect(described_class.parse(body)).to eq(['4.9.0', '4.10.0', '4.12.0', '4.16.0'])
    end

    ['{"secret":"x"}', "---\ngarbage deps\n", "---\n", '---', ''].each do |bad|
      it "rejects #{bad.inspect} without echoing it" do
        expect { described_class.parse(bad) }.to raise_error(ArgumentError, 'unexpected Core index response')
      end
    end
  end

  describe '#initialize' do
    it 'requires a token' do
      expect { described_class.new(token: '') }.to raise_error(ArgumentError, 'PUPPET_FORGE_TOKEN is not set')
    end
  end

  describe '#facter_versions' do
    let(:token) { 'not-a-real-token' }
    let(:http) { instance_double(Net::HTTP) }

    before(:each) { allow(Net::HTTP).to receive(:start).and_yield(http) }

    it 'returns parsed versions on 200 and sends basic auth' do
      sent = nil
      allow(http).to receive(:request) { |req| (sent = req) && instance_double(Net::HTTPResponse, code: '200', body: body) }
      expect(described_class.new(token: token).facter_versions).to include('4.12.0')
      expect(sent['authorization']).to start_with('Basic ')
    end

    it 'raises with the status only on failure' do
      allow(http).to receive(:request).and_return(instance_double(Net::HTTPResponse, code: '401', body: 'denied'))
      expect { described_class.new(token: token).facter_versions }.to raise_error(RuntimeError, %r{HTTP 401}) { |e| expect(e.message).not_to include(token) }
    end
  end
end
