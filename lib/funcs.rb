require 'octokit'
require 'filecache'
def cache
  @_cache = FileCache.new("replacer-cache", "/tmp/replacer-cache", 1800, 3)
end

def client
  @_octokit ||= Octokit::Client.new(
    api_endpoint: ENV['GITHUB_API'] || 'api.github.com',
    access_token: ENV['GITHUB_TOKEN'],
    auto_paginate: true,
    per_page: 300
  )
end

def repos
  cache.get_or_set("repos") do
    client.organizations.map do |o|
      client.organization_repositories(o[:login]).map do |repo|
        repo[:full_name]
      end
    end.flatten.compact
  end
end
