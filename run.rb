# frozen_string_literal: true

require 'base64'
require 'digest/sha1'
require 'yaml'
require 'ostruct'
require 'parallel'
require 'logger'
require './lib/funcs'
logger = Logger.new($stdout)

def cols
  %w[
    repo_pattern
    file_pattern
    content_pattern
    replace
  ]
end

def config
  @config ||= YAML.load_file(ENV['CONFIG_PATH'] || './config.yml').select do |_name, rc|
    rc.keys == cols
  end.to_h
end

def pr_title(name)
  "Replace by #{name}(github-replacer)"
end

def branch_name(name)
  "replacer-update-#{name}"
end

Parallel.each(repos, in_threads: 4) do |repo_name|
  logger.info "repo:#{repo_name} start processing"

  # PRが存在していない設定だけを取得
  has_not_pr_config = config.select { |_name, rc| repo_name =~ /#{rc['repo_pattern']}/ }.select do |name, _rc|
    begin
      b = client.ref(repo_name, "heads/#{branch_name(name)}")
      if b && client.pull_requests(repo_name).none? { |pr| pr[:title] == pr_title(name) }
        client.delete_branch(repo_name, branch_name(name))
        return true
      else
        logger.info "rule:#{name} repo:#{repo_name} already create pull request"
        next
      end
    rescue Octokit::NotFound
    rescue StandardError => e
      logger.error e.inspect
    end
    true
  end

  has_not_pr_config.empty? && next
  logger.info "repo:#{repo_name} has match rules"

  default_branch = client.repo(repo_name).default_branch

  results = {}
  # リポジトリのファイルをすべてのルール処理する
  client.tree(
    repo_name,
    default_branch,
    recursive: true
  )[:tree].select { |obj| obj[:type] == 'blob' }.each do |obj|
    before_content = nil
    has_not_pr_config.each do |name, rc|
      c = OpenStruct.new(rc)
      next unless obj[:path] =~ /#{c.file_pattern}/

      before_content ||= Base64.decode64(client.contents(repo_name, ref: default_branch, path: obj[:path])[:content])
      after_content = before_content.gsub(/#{c.content_pattern}/m, c.replace)
      next if after_content == before_content

      logger.info "rule:#{name} repo:#{repo_name} file:#{obj[:path]} modified"
      results[name] ||= []
      results[name] << {
        file_info: obj,
        after: after_content
      }
    end
  end

  # ブランチの作成
  results.each do |name, update_results|
    begin
      unless ENV['DRY_RUN']
        client.create_ref(
          repo_name,
          "refs/heads/#{branch_name(name)}",
          client.ref(repo_name, "heads/#{default_branch}").object.sha
        )
      end
    rescue Octokit::Forbidden => e
      next
    rescue StandardError => e
      raise e
    end
    # 結果をリモートリポジトリに反映する
    update_results.each do |r|
      logger.info "repo:#{repo_name} file:#{r[:file_info][:path]} update content"
      next if ENV['DRY_RUN']

      client.update_contents(repo_name,
                             r[:file_info][:path],
                             "replace #{name} - #{r[:file_info][:path]}",
                             r[:file_info][:sha],
                             r[:after],
                             branch: branch_name(name))
    end

    c = OpenStruct.new(config[name])
    pr_body = <<~EOS
      This PR contains the following updates:
      | Pattern Name | Pattern | Replace |
      |---|---|---|
      | #{name} | #{c.content_pattern}| #{c.replace}|

      ### Updated Files
      #{update_results.map { |r| "- #{r[:file_info][:path]}" }.join("\n")}
    EOS

    logger.info "repo:#{repo_name} create pull request"
    unless ENV['DRY_RUN']
      client.create_pull_request(repo_name, default_branch, branch_name(name),
                                 pr_title(name), pr_body)
    end
  end
rescue StandardError => e
  logger.error e.inspect
  logger.error e.backtrace
  begin
    if client.rate_limit.remaining / client.rate_limit.limit < 0.1
      sleep client.rate_limit.resets_in
      retry
    end
  rescue StandardError => e
    logger.warn "maybe rate limit is not enabled. #{e.inspect}"
  end
  next
end
