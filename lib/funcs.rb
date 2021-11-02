# frozen_string_literal: true

require 'octokit'
require 'filecache'
require 'faraday-http-cache'
def cache
  @_cache = FileCache.new('replacer-cache', '/tmp/replacer-cache', 1800, 3)
end

def client
  unless @_octokit
    @_octokit = Octokit::Client.new(
      api_endpoint: ENV['GITHUB_API'] || 'https://api.github.com',
      access_token: ENV['GITHUB_TOKEN'],
      auto_paginate: true,
      per_page: 100
    )
    stack = Faraday::RackBuilder.new do |builder|
      builder.use Faraday::HttpCache, serializer: Marshal, shared_cache: false
      builder.use Octokit::Response::RaiseError
      builder.adapter Faraday.default_adapter
    end
    Octokit.middleware = stack
  end
  @_octokit
end

def repos
  @_repos ||= cache.get_or_set('repos'){ client.repositories.map(&:full_name).uniq }
end
