module Filters
  class Dependents 
    def initialize(pull_requests:, input: Input.instance)
      @pull_requests = pull_requests
      @input = input
    end

    def pull_requests
      if @input.source.check_dependent_prs
        @memoized ||= @pull_requests.delete_if {|x| !x.dependent_prs_merged? }
      else
        @pull_requests
      end
    end
  end
end
