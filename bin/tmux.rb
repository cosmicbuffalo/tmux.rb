#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "tmux/cli"

exit Tmux::CLI.run(ARGV)
