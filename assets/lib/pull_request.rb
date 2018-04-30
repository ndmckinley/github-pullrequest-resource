# frozen_string_literal: true

require 'octokit'

class PullRequest
  def self.from_github(repo:, id:)
    pr = Octokit.pull_request(repo.name, id)
    PullRequest.new(pr: pr)
  end

  def initialize(pr:)
    @pr = pr
  end

  def from_fork?
    base_repo != head_repo
  end

  def review_approved?
    Octokit.pull_request_reviews(base_repo, id).any? { |r| r['state'] == 'APPROVED' }
  end

  def author_associated?
    # Checks whether the author is associated with the repo that the PR is against:
    # either the owner of that repo, someone invited to collaborate, or a member
    # of the organization who owns that repository.
    %w[OWNER COLLABORATOR MEMBER].include? @pr['author_association']
  end

  def dependent_prs_merged?
    # For all comments on the pull request...
    comments = Octokit.issue_comments(base_repo, id)
    !comments.empty? && comments.all? do |c|
      # If they're by someone we trust...
      return true unless %w(OWNER COLLABORATOR MEMBER CONTRIBUTOR).include?(c['author_association'])
      # Confirm that any PR they reference as a dependency is merged.
      c[:body].scan(/depends: https:\/\/github.com\/(?<user>\w*)\/(?<repo>[\w-]*)\/pull\/(?<pr>\d*)/).all? {
        |m| Octokit.pull_request(m[0] + "/" + m[1], m[2])['merged']
      }
    end
  end

  def equals?(id:, sha:)
    [self.sha, self.id.to_s] == [sha, id.to_s]
  end

  def to_json(*)
    as_json.to_json
  end

  def as_json
    { 'ref' => sha, 'pr' => id.to_s }
  end

  def id
    @pr['number']
  end

  def sha
    @pr['head']['sha']
  end

  def url
    @pr['html_url']
  end

  private

  def base_repo
    @pr['base']['repo']['full_name']
  end

  def head_repo
    @pr['head']['repo']['full_name']
  end
end
