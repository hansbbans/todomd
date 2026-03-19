#!/usr/bin/env ruby

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

class AppStoreConnectClient
  DEFAULT_BASE_URL = 'https://api.appstoreconnect.apple.com'.freeze
  TOKEN_LIFETIME_SECONDS = 19 * 60

  def initialize(key_id:, issuer_id:, private_key_path:, base_url: DEFAULT_BASE_URL)
    @key_id = key_id
    @issuer_id = issuer_id
    @private_key = OpenSSL::PKey.read(File.read(private_key_path))
    @base_url = base_url
    @token = nil
    @token_expires_at = Time.at(0)
  end

  def get(path, params = {})
    request(:get, build_uri(path, params))
  end

  def get_all(path, params = {})
    results = []
    next_uri = build_uri(path, params)

    while next_uri
      response = request(:get, next_uri)
      results.concat(Array(response['data']))
      next_link = response.dig('links', 'next')
      next_uri = next_link && !next_link.empty? ? URI(next_link) : nil
    end

    results
  end

  def post(path, payload)
    request(:post, build_uri(path), payload)
  end

  private

  def build_uri(path, params = {})
    uri = URI.join(@base_url, path)
    unless params.empty?
      uri.query = URI.encode_www_form(params)
    end
    uri
  end

  def request(method, uri, payload = nil)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request_class = case method
                    when :get then Net::HTTP::Get
                    when :post then Net::HTTP::Post
                    else
                      raise "Unsupported request method: #{method}"
                    end

    request = request_class.new(uri)
    request['Authorization'] = "Bearer #{authorization_token}"
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(payload) if payload

    response = http.request(request)
    body = response.body.to_s
    parsed = body.empty? ? {} : JSON.parse(body)

    return parsed if response.code.to_i.between?(200, 299)

    detail = Array(parsed['errors']).map { |error| error['detail'] }.compact.join(' | ')
    detail = body if detail.empty?
    raise "App Store Connect API #{response.code} for #{uri}: #{detail}"
  end

  def authorization_token
    if @token.nil? || Time.now >= @token_expires_at
      header = { alg: 'ES256', kid: @key_id, typ: 'JWT' }
      payload = {
        iss: @issuer_id,
        aud: 'appstoreconnect-v1',
        exp: Time.now.to_i + TOKEN_LIFETIME_SECONDS
      }

      encoded_header = Base64.urlsafe_encode64(JSON.generate(header), padding: false)
      encoded_payload = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
      signing_input = "#{encoded_header}.#{encoded_payload}"
      der_signature = @private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
      signature = der_to_raw_signature(der_signature, 32)
      encoded_signature = Base64.urlsafe_encode64(signature, padding: false)

      @token = "#{signing_input}.#{encoded_signature}"
      @token_expires_at = Time.at(payload[:exp] - 30)
    end

    @token
  end

  def der_to_raw_signature(der_signature, component_size)
    asn1 = OpenSSL::ASN1.decode(der_signature)
    raise 'Unexpected ECDSA signature structure' unless asn1.is_a?(OpenSSL::ASN1::Sequence) && asn1.value.length == 2

    asn1.value.map { |component| integer_to_fixed_bytes(component.value, component_size) }.join
  end

  def integer_to_fixed_bytes(value, size)
    hex = value.to_s(16)
    hex = "0#{hex}" if hex.length.odd?
    hex = hex.rjust(size * 2, '0')
    raise "ECDSA signature component is too large for #{size} bytes" if hex.length > size * 2

    [hex].pack('H*')
  end
end

def required_env(name)
  value = ENV[name].to_s.strip
  raise "Missing required environment variable #{name}" if value.empty?

  value
end

def parse_group_list(value)
  value.to_s.split(/[,\n]/).map(&:strip).reject(&:empty?).uniq
end

def find_app_id(client, bundle_id)
  apps = client.get_all('/v1/apps', 'filter[bundleId]' => bundle_id, 'limit' => '200')
  app = apps.find { |item| item.dig('attributes', 'bundleId') == bundle_id }
  raise "No App Store Connect app found for bundle ID #{bundle_id}" unless app

  app['id']
end

def build_number_for(candidate)
  attributes = candidate.fetch('attributes', {})

  # App Store Connect exposes the uploaded build number as the build resource's
  # version attribute. Keep supporting buildNumber too in case Apple changes the
  # payload shape or older endpoints behave differently.
  attributes['buildNumber'] || attributes['version']
end

def find_build_for_pre_release_version(client, pre_release_version_id:, build_number:)
  builds = client.get_all("/v1/preReleaseVersions/#{pre_release_version_id}/builds", 'limit' => '200')
  builds.find { |candidate| build_number_for(candidate).to_s == build_number.to_s }
end

def find_build(client, app_id:, version:, build_number:)
  pre_release_versions = client.get_all(
    '/v1/preReleaseVersions',
    'filter[app]' => app_id,
    'filter[version]' => version,
    'limit' => '200'
  )

  pre_release_versions.each do |pre_release_version|
    build = find_build_for_pre_release_version(
      client,
      pre_release_version_id: pre_release_version.fetch('id'),
      build_number: build_number
    )
    return build if build
  end

  # Fall back to scanning all builds for the app in case the prerelease-version
  # lookup lags behind what App Store Connect shows in the UI.
  builds = client.get_all('/v1/builds', 'filter[app]' => app_id, 'limit' => '200')
  builds.find { |candidate| build_number_for(candidate).to_s == build_number.to_s }
end

def poll_for_build(client, app_id:, version:, build_number:, timeout_seconds: 1800, interval_seconds: 30)
  deadline = Time.now + timeout_seconds

  loop do
    build = find_build(
      client,
      app_id: app_id,
      version: version,
      build_number: build_number
    )
    if build
      processing_state = build.dig('attributes', 'processingState')
      puts "Found build #{build_number} for version #{version} with processing state #{processing_state}."

      case processing_state
      when 'VALID'
        return build
      when 'FAILED', 'INVALID'
        raise "Build #{build_number} finished in #{processing_state} state and cannot be assigned to TestFlight groups."
      end
    else
      puts "Waiting for build #{build_number} for version #{version} to appear in App Store Connect..."
    end

    raise "Timed out waiting for build #{build_number} for version #{version} to finish processing." if Time.now >= deadline

    sleep interval_seconds
  end
end

def fetch_groups(client, app_id:, internal:)
  groups = client.get_all('/v1/betaGroups', 'filter[app]' => app_id, 'limit' => '200')
  groups.select { |group| group.dig('attributes', 'isInternalGroup') == internal }
end

def resolve_groups(groups, requested_names_or_ids, label)
  requested_names_or_ids.map do |requested|
    match = groups.find do |group|
      group['id'] == requested ||
        group.dig('attributes', 'name') == requested ||
        group.dig('attributes', 'name').to_s.casecmp?(requested)
    end

    next match if match

    available = groups.map { |group| group.dig('attributes', 'name') }.sort.join(', ')
    raise "Could not find #{label} TestFlight group #{requested.inspect}. Available #{label} groups: #{available}"
  end
end

def assigned_group_ids(client, build_id)
  client.get_all("/v1/builds/#{build_id}/betaGroups", 'limit' => '200').map { |group| group['id'] }.to_set
end

def attach_build_to_groups(client, build_id:, groups:)
  require 'set'

  existing_group_ids = assigned_group_ids(client, build_id)

  groups.each do |group|
    group_id = group['id']
    group_name = group.dig('attributes', 'name')

    if existing_group_ids.include?(group_id)
      puts "Build is already assigned to #{group_name}."
      next
    end

    client.post(
      "/v1/betaGroups/#{group_id}/relationships/builds",
      data: [{ type: 'builds', id: build_id }]
    )

    puts "Assigned build to #{group_name}."
  end
end

client = AppStoreConnectClient.new(
  key_id: required_env('APP_STORE_CONNECT_KEY_ID'),
  issuer_id: required_env('APP_STORE_CONNECT_ISSUER_ID'),
  private_key_path: required_env('AUTH_KEY_PATH'),
  base_url: ENV.fetch('APP_STORE_CONNECT_BASE_URL', AppStoreConnectClient::DEFAULT_BASE_URL)
)

bundle_id = required_env('APP_BUNDLE_ID')
version = required_env('APP_VERSION')
build_number = required_env('BUILD_NUMBER')
internal_groups = parse_group_list(ENV['INTERNAL_GROUPS'])
external_groups = parse_group_list(ENV['EXTERNAL_GROUPS'])
wait_timeout_seconds = Integer(ENV.fetch('WAIT_TIMEOUT_SECONDS', '1800'))
poll_interval_seconds = Integer(ENV.fetch('POLL_INTERVAL_SECONDS', '30'))

if internal_groups.empty? && external_groups.empty?
  puts 'No TestFlight groups requested; skipping assignment.'
  exit 0
end

app_id = find_app_id(client, bundle_id)
puts "Resolved App Store Connect app ID #{app_id} for #{bundle_id}."

build = poll_for_build(
  client,
  app_id: app_id,
  version: version,
  build_number: build_number,
  timeout_seconds: wait_timeout_seconds,
  interval_seconds: poll_interval_seconds
)
build_id = build.fetch('id')

unless internal_groups.empty?
  groups = fetch_groups(client, app_id: app_id, internal: true)
  attach_build_to_groups(
    client,
    build_id: build_id,
    groups: resolve_groups(groups, internal_groups, 'internal')
  )
end

unless external_groups.empty?
  groups = fetch_groups(client, app_id: app_id, internal: false)
  attach_build_to_groups(
    client,
    build_id: build_id,
    groups: resolve_groups(groups, external_groups, 'external')
  )
end
