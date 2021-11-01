require 'base64'
require 'digest/sha1'
require 'yaml'
require 'ostruct'
require 'logger'
require './lib/funcs'
logger = Logger.new(STDOUT)

cols = %w(
  repo_pattern
  file_pattern
  content_pattern
  replace
)

YAML.load_file(ENV['COFIG_PATH'] || './config.yml').each do |name,rc|
  unless rc.keys == cols
    logger.warn("#{name} is not filled all parameter keys")
    next
  end
  c = OpenStruct.new(rc)
  if targets = repos.select {|r| r =~ /#{c.repo_pattern}/ }
    targets.each do |repo_name|
      pr_title = "Replace by #{name}(github-replacer)"

      begin
        default_branch = client.repo(repo_name).default_branch
        branch_name = "replacer-update-#{name}"

        begin
          client.ref(repo_name, "heads/#{branch_name}")
          if client.pull_requests(repo_name).none? {|pr| pr[:title] == pr_title }
            client.delete_branch(repo_name, branch_name)
          else
            next
          end
          logger.info "rule:#{name} repo:#{repo_name} start processing"
        rescue Octokit::NotFound
        rescue => e
          logger.error e.inspect
          next
        end

        target_files = client.tree(
          repo_name,
          default_branch,
          recursive: true)[:tree].select {|obj| obj[:type] == 'blob' && obj[:path] =~ /#{c.file_pattern}/ }

          results = target_files.map do |t|
            cs = client.contents(repo_name, ref: default_branch, path: t[:path])
            content = Base64.decode64(cs[:content])

            if content.gsub!(/#{c.content_pattern}/m, c.replace)
              logger.info "rule:#{name} repo:#{repo_name} file:#{t[:path]} modified"
              {
                file_info: t,
                after: content
              }
            end
          end.compact

          if results && results.size > 0
            begin
              client.create_ref(
                repo_name,
                "refs/heads/#{branch_name}",
                client.ref(repo_name, "heads/#{default_branch}").object.sha)
            rescue Octokit::Forbidden => e
              next
            rescue => e
              raise e
            end
            results.each do |r|
              client.update_contents(repo_name,
                                     r[:file_info][:path],
                                     "replace #{name} - #{r[:file_info][:path]}",
                                     r[:file_info][:sha],
                                     r[:after],
                                     branch: branch_name
                                    )
            end

            pr_body = <<~EOS
            This PR contains the following updates:
            | Pattern Name | Pattern | Replace |
            |---|---|---|
            | #{name} | #{c.content_pattern}| #{c.replace}|

            ### Updated Files
            #{results.map{|r|"- #{r[:file_info][:path]}"}.join("\n")}
            EOS

            client.create_pull_request(repo_name, default_branch, branch_name,
                                       pr_title, pr_body)
        end
      rescue => e
        logger.error e.inspect
        next
      end
    end
  end
end
