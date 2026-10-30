# frozen_string_literal: true

module Tmux
  # Lets a configuration file `require` the Ruby module of an installed tmux
  # plugin by name, such as `require "tmux-ai-attn"`, however the plugin was
  # installed: by TPM, by hand, or by another tool.
  #
  # A plugin opts in by shipping lib/<its directory name>.rb. Its lib
  # directory then joins the end of $LOAD_PATH, after -I, RUBYLIB, and
  # anything already there. Plugins that have not opted in are never added,
  # so their files cannot shadow another library.
  module Plugins
    # Where plugins are looked up, in order: each --plugin-path, then each
    # entry of TMUX_RB_PLUGIN_PATH (separated like PATH), then TPM's plugin
    # directory. Each is a plugin checkout or a directory of them. The first
    # copy of a plugin found wins, so an explicit path overrides TPM's copy.
    def self.search_path(env = ENV, extra: [])
      configured = env.fetch("TMUX_RB_PLUGIN_PATH", "").split(File::PATH_SEPARATOR).reject(&:empty?)
      (extra + configured + tpm_directories(env)).map { |path| File.expand_path(path) }.uniq
    end

    # TMUX_PLUGIN_MANAGER_PATH, which TPM sets in tmux's global environment,
    # or else TPM's default locations.
    def self.tpm_directories(env = ENV)
      if (path = env["TMUX_PLUGIN_MANAGER_PATH"]) && !path.empty?
        return [path]
      end

      config_home = env["XDG_CONFIG_HOME"]
      config_home = File.join(Dir.home, ".config") if config_home.nil? || config_home.empty?
      [File.join(Dir.home, ".tmux", "plugins"), File.join(config_home, "tmux", "plugins")]
    end

    # The lib directories of the opted-in plugins on the search path, one per
    # plugin name, in search order.
    def self.load_paths(env = ENV, extra: [])
      found = {}
      search_path(env, extra:).each do |path|
        checkouts = opted_in?(path) ? [path] : Dir.glob(File.join(path, "*")).sort.select { |dir| opted_in?(dir) }
        checkouts.each { |checkout| found[File.basename(checkout)] ||= File.join(checkout, "lib") }
      end
      found.values
    end

    def self.add_to_load_path(env = ENV, extra: [])
      load_paths(env, extra:).each { |lib| $LOAD_PATH << lib unless $LOAD_PATH.include?(lib) }
    end

    def self.opted_in?(checkout) = File.file?(File.join(checkout, "lib", "#{File.basename(checkout)}.rb"))
    private_class_method :opted_in?
  end
end
