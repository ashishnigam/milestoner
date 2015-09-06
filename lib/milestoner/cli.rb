require "yaml"
require "thor"
require "thor/actions"
require "thor_plus/actions"

module Milestoner
  # The Command Line Interface (CLI) for the gem.
  class CLI < Thor
    include Thor::Actions
    include ThorPlus::Actions

    package_name Milestoner::Identity.label

    # Initialize.
    def initialize args = [], options = {}, config = {}
      super args, options, config
    end

    desc "-v, [--version]", "Show version."
    map %w(-v --version) => :version
    def version
      say Milestoner::Identity.label_version
    end

    desc "-h, [--help=HELP]", "Show this message or get help for a command."
    map %w(-h --help) => :help
    def help task = nil
      say && super
    end
  end
end
