# frozen_string_literal: true

require 'spec_helper'
require 'puppetlabs/facterdb/tools'

RSpec.describe Puppetlabs::FacterDB::Tools::GemIndex do
  let(:token) { 'test-token-not-real' }
  let(:fixture) { File.read(File.expand_path('../../../fixtures/gem_index/facter_versions.json', __dir__)) }

  let(:fake_http) do
    Class.new do
      attr_reader :host, :port, :options, :sent

      def initialize(response)
        @response = response
      end

      def start(host, port, **options)
        @host = host
        @port = port
        @options = options
        yield self
      end

      def request(req)
        @sent = req
        @response
      end
    end
  end

  def reply(klass, code, body)
    klass.new('1.1', code, '').tap { |r| allow(r).to receive(:body).and_return(body) }
  end

  def index_with(response)
    http = fake_http.new(response)
    [described_class.new(token: token, http: http), http]
  end

  describe '#versions' do
    let(:ok) { reply(Net::HTTPOK, '200', fixture) }

    it 'returns sorted unique non-prerelease ruby-platform versions' do
      index, = index_with(ok)
      expect(index.versions).to eq(['4.11.0', '4.12.0', '4.13.0', '4.23.0'])
    end

    it 'connects over https to the Core gem host' do
      index, http = index_with(ok)
      index.versions
      expect([http.host, http.port, http.options[:use_ssl]]).to eq(['rubygems-puppetcore.puppet.com', 443, true])
    end

    it 'sends Basic forge-key auth' do
      index, http = index_with(ok)
      index.versions
      expect(http.sent['authorization']).to eq("Basic #{["forge-key:#{token}"].pack('m0')}")
    end

    it 'keeps the credential out of the request path' do
      index, http = index_with(ok)
      index.versions
      expect(http.sent.path).to eq('/api/v1/versions/facter.json')
    end

    it 'raises an Error naming the status code on failure' do
      index, = index_with(reply(Net::HTTPUnauthorized, '401', "bad credential #{token}"))
      expect { index.versions }.to raise_error(described_class::Error, %r{401})
    end

    it 'never puts the token or response body in the error message' do
      index, = index_with(reply(Net::HTTPUnauthorized, '401', "bad credential #{token}"))
      expect { index.versions }.to raise_error(described_class::Error, %r{\A(?!.*test-token-not-real)})
    end
  end

  describe '.new' do
    [nil, ''].each do |value|
      it "raises ArgumentError for token #{value.inspect}" do
        expect { described_class.new(token: value) }.to raise_error(ArgumentError, 'PUPPET_FORGE_TOKEN is not set')
      end
    end

    it 'omits the token from inspect' do
      expect(described_class.new(token: token).inspect).not_to include(token)
    end
  end
end
