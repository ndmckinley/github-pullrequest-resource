#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../repository'
require_relative '../status'

module Commands
  class Out < Commands::Base
    attr_reader :destination

    def initialize(destination:, input: Input.instance)
      @destination = destination

      super(input: input)
    end

    def output
      check_defaults!
      path = File.join(destination, params['path'])
      raise %(`path` "#{params['path']}" does not exist) unless File.exist?(path)

      if params.comment
        comment_path = File.join(destination, params.comment)
        raise %(`comment` "#{params.comment}" does not exist) unless File.exist?(comment_path)
      end

      if params.merge.commit_msg
        commit_path = File.join(destination, params.merge.commit_msg)
        raise %(`merge.commit_msg` "#{params.merge.commit_msg}" does not exist) unless File.exist?(commit_path)
      end

      id  = Dir.chdir(path) { `git config --get pullrequest.id`.chomp }
      sha = Dir.chdir(path) { `git rev-parse HEAD`.chomp }

      repo = Repository.new(name: input.source.repo)

      metadata = [{ 'name' => 'status', 'value' => params['status'] }]
      if id.empty?
        version = { 'ref' => sha }
      else
        pr = PullRequest.from_github(repo: repo, id: id)
        if sha == pr.merge_commit_sha
          # If the SHA that we have here is the merge commit's SHA,
          # we know that the correct SHA is the one at the tip of
          # the PR (which might be the same as the merge SHA if
          # there's no need for a merge).
          sha = pr.sha
        end
        metadata << { 'name' => 'url', 'value' => pr.url }
        version = { 'pr' => id, 'ref' => sha }
      end

      atc_url = input.source.base_url || ENV['ATC_EXTERNAL_URL']
      contextes = params.context || ['status']
      contextes = [contextes] unless contextes.is_a?(Array)

      contextes.each do |context|
        Status.new(
          state: params.status,
          atc_url: whitelist(context: atc_url),
          sha: sha,
          repo: repo,
          context: whitelist(context: context)
        ).create!
      end

      if params.comment
        comment_path = File.join(destination, params.comment)
        comment = File.read(comment_path, encoding: Encoding::UTF_8)
        Octokit.add_comment(input.source.repo, id, comment)
        metadata << { 'name' => 'comment', 'value' => comment }
      end

      if params.assignee_file
        assignee_path = File.join(destination, params.assignee_file)
        assignee = File.read(assignee_path, encoding: Encoding::UTF_8)
        Octokit.add_assignees(input.source.repo, id, [assignee])
      end

      if params.label
        label = if params.label.is_a?(Array)
                  params.label
                else
                  [params.label]
                end
        Octokit.add_labels_to_an_issue(input.source.repo, id, label)
        metadata << { 'name' => 'label', 'value' => label.to_s }
      end

      if params.label_file
        label_path = File.join(destination, params.label_file)
        labels = File.read(label_path, encoding: Encoding::UTF_8)
        labels_array = labels.split(',').map(&:strip)
        Octokit.add_labels_to_an_issue(input.source.repo, id, labels_array)
        metadata << { 'name' => 'label', 'value' => labels_array.to_s }
      end

      if params.merge.method
        commit_msg = if params.merge.commit_msg
                       commit_path = File.join(destination, params.merge.commit_msg)
                       File.read(commit_path, encoding: Encoding::UTF_8)
                     else
                       ''
                     end
        tries = 0
        begin
          tries += 1
          Octokit.merge_pull_request(input.source.repo, id, commit_msg, merge_method: params.merge.method, accept: 'application/vnd.github.polaris-preview+json')
        rescue Octokit::ClientError
          if tries < 3
            sleep 10
            retry
          else
            raise
          end
        rescue Octokit::ServerError
          if tries < 5
            sleep 10
            retry
          else
            raise
          end
        end
        metadata << { 'name' => 'merge', 'value' => params.merge.method }
        metadata << { 'name' => 'merge_commit_msg', 'value' => commit_msg }
      end

      {
        'version' => version,
        'metadata' => metadata
      }
    end

    private

    def whitelist(context:)
      c = context.dup
      %w[BUILD_ID BUILD_NAME BUILD_JOB_NAME BUILD_PIPELINE_NAME BUILD_TEAM_NAME ATC_EXTERNAL_URL].each do |name|
        c.gsub!("$#{name}", ENV[name] || '')
      end
      c
    end

    def params
      input.params
    end

    def check_defaults!
      raise %(`status` "#{params.status}" is not supported -- only success, failure, error, or pending) unless %w[success failure error pending].include?(params.status)
      raise %(`merge.method` "#{params.merge.method}" is not supported -- only merge, squash, or rebase) if params.merge.method && !%w[merge squash rebase].include?(params.merge.method)
      raise '`path` required in `params`' unless params.path
    end
  end
end

if $PROGRAM_NAME == __FILE__
  destination = ARGV.shift
  command = Commands::Out.new(destination: destination)
  puts JSON.generate(command.output)
end
