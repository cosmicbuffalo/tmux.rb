#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "shellwords"

module OhMyTmuxRuntime
  module_function

  def tmux(*arguments, allow_failure: false)
    stdout, stderr, status = Open3.capture3("tmux", *arguments)
    return stdout if status.success? || allow_failure

    raise "tmux #{arguments.join(' ')} failed: #{stderr}"
  end

  def set_user_option(name, value)
    if value.nil? || value.to_s.empty?
      tmux("set-option", "-gu", "@#{name}", allow_failure: true)
    else
      tmux("set-option", "-g", "@#{name}", value.to_s, allow_failure: true)
    end
  end

  def update_metrics
    update_uptime
    update_battery
  end

  def update_uptime
    seconds = if File.readable?("/proc/uptime")
      File.read("/proc/uptime").split.first.to_f.to_i
    else
      stdout, = Open3.capture2("sysctl", "-n", "kern.boottime")
      boot = stdout[/sec\s*=\s*(\d+)/, 1] || stdout[/\A\s*(\d+)/, 1]
      boot ? Time.now.to_i - boot.to_i : nil
    end

    values = if seconds
      {
        uptime_y: seconds / 31_536_000,
        uptime_dy: (seconds / 86_400) % 365,
        uptime_d: seconds / 86_400,
        uptime_h: (seconds / 3600) % 24,
        uptime_m: (seconds / 60) % 60,
        uptime_s: seconds % 60
      }
    else
      {}
    end
    %i[uptime_y uptime_dy uptime_d uptime_h uptime_m uptime_s].each do |name|
      set_user_option(name, values[name])
    end
  rescue Errno::ENOENT
    nil
  end

  def update_battery
    batteries = Dir["/sys/class/power_supply/*"].filter_map do |path|
      next unless File.basename(path).match?(/bat/i)
      scope_path = File.join(path, "scope")
      next if File.file?(scope_path) && File.read(scope_path).strip.casecmp?("device")

      capacity = Integer(File.read(File.join(path, "capacity")).strip, exception: false)
      next unless capacity

      status = File.read(File.join(path, "status")).strip rescue ""
      [capacity.clamp(0, 100), status]
    end

    if batteries.empty?
      %i[battery_percentage battery_charge battery_status battery_discharging battery_bar].each do |name|
        set_user_option(name, nil)
      end
      return
    end

    percentage = batteries.sum(&:first) / batteries.length
    discharging = batteries.any? { |(_, status)| status.casecmp?("discharging") }
    set_user_option(:battery_percentage, "#{percentage}%")
    set_user_option(:battery_charge, percentage.fdiv(100))
    set_user_option(:battery_discharging, discharging ? 1 : 0)
    set_user_option(:battery_status, discharging ? "↓" : "↑")
    set_user_option(:battery_bar, battery_bar(percentage))
  end

  def battery_bar(percentage)
    palette = %w[colour196 colour202 colour208 colour214 colour220 colour226
      colour190 colour154 colour118 colour82 colour46]
    length = 4
    full = (percentage.fdiv(100) * length).round
    Array.new(length) do |index|
      color = palette[(index * palette.length / length).clamp(0, palette.length - 1)]
      "#[fg=#{color}]#{index < full ? '◼' : '◻'}"
    end.join
  end

  def metrics_loop(interval)
    stopped = false
    Signal.trap("TERM") { stopped = true }
    Signal.trap("INT") { stopped = true }
    until stopped
      break if tmux("display-message", "-p", '#{pid}', allow_failure: true).empty?

      update_metrics
      interval.times do
        break if stopped
        sleep 1
      end
    end
  end

  def pane_info(pane_pid, pane_tty)
    tty = pane_tty.to_s.delete_prefix("/dev/")
    arguments = if RUBY_PLATFORM.include?("linux")
      ["-t", tty, "--sort=lstart"]
    else
      ["-t", "/dev/#{tty}"]
    end
    stdout, = Open3.capture2("ps", *arguments, "-o", "user=", "-o", "pid=",
      "-o", "ppid=", "-o", "command=")
    records = stdout.lines.filter_map do |line|
      match = line.match(/\A\s*(\S+)\s+(\d+)\s+(\d+)\s+(.*)\z/)
      next unless match
      next if match[4].match?(/(?:^|[\s\/])tee(?:\s|$)/)
      next if match[4].include?("ssh") && match[4].match?(/-W|tsh proxy ssh|sss_ssh_knownhostsproxy/)

      {user: match[1], pid: match[2], ppid: match[3], command: match[4]}
    end
    by_pid = records.to_h { |record| [record[:pid], record] }
    children = {}
    records.each { |record| children[record[:ppid]] ||= record[:pid] }

    pid = pane_pid.to_s
    while children[pid]
      break if by_pid.dig(pid, :command).to_s.match?(%r{(?:^|/)ssh\s})
      pid = children.fetch(pid)
    end
    by_pid[pid] || by_pid[pane_pid.to_s] || {user: ENV.fetch("USER", ""), command: ""}
  rescue Errno::ENOENT
    {user: ENV.fetch("USER", ""), command: ""}
  end

  def ssh_arguments(command)
    words = Shellwords.split(command)
    index = words.index { |word| File.basename(word) == "ssh" }
    index ? words[(index + 1)..] : nil
  rescue ArgumentError
    nil
  end

  def ssh_config(arguments)
    stdout, = Open3.capture2e("ssh", "-G", *arguments)
    stdout.lines.to_h do |line|
      name, value = line.split(/\s+/, 2)
      [name, value&.strip]
    end
  rescue Errno::ENOENT
    {}
  end

  def username(pane_pid, pane_tty, ssh_only)
    info = pane_info(pane_pid, pane_tty)
    arguments = ssh_arguments(info[:command])
    return ssh_config(arguments)["user"].to_s if arguments
    return "" if truthy?(ssh_only)

    info[:user].to_s
  end

  def hostname(pane_pid, pane_tty, ssh_only, full, local_hostname)
    info = pane_info(pane_pid, pane_tty)
    arguments = ssh_arguments(info[:command])
    if arguments
      host = ssh_config(arguments)["hostname"].to_s
      return "localhost" if host == "127.0.0.1" && !truthy?(full)
      return host.split(".", 2).first unless truthy?(full)
      return host
    end
    truthy?(ssh_only) ? "" : local_hostname
  end

  def truthy?(value)
    %w[1 true yes enabled].include?(value.to_s.downcase)
  end

  def maximize(session, pane)
    panes = tmux("list-panes", "-s", "-t", session, "-F",
      '#{pane_dead}\t#{pane_id}\t#{pane_start_command}').lines.map { |line| line.chomp.split("\t", 3) }
    placeholder = panes.find do |dead, _id, command|
      dead == "1" && command.to_s.include?("oh-my-tmux-maximized #{pane}")
    end
    if placeholder
      tmux("swap-pane", "-s", placeholder[1], "-t", pane)
      tmux("kill-pane", "-t", placeholder[1])
      return
    end

    if tmux("list-panes", "-t", "#{session}:").lines.length == 1
      tmux("display-message", "Can't maximize with only one pane")
      return
    end

    command = "sh -c 'sleep 0.2' oh-my-tmux-maximized #{Shellwords.escape(pane)}"
    info = tmux("new-window", "-d", "-t", "#{session}:", "-F",
      '#{session_name}:#{window_index}.#{pane_id}', "-P", command).strip
    target_window, target_pane = info.split(".", 2)
    tmux("set-window-option", "-t", target_window, "remain-on-exit", "on")
    20.times do
      break if tmux("display-message", "-p", "-t", target_pane, '#{pane_dead}') == "1\n"
      sleep 0.1
    end
    tmux("set-window-option", "-t", target_window, "remain-on-exit", "off")
    tmux("swap-pane", "-s", pane, "-t", target_pane)
  end

  def fpp(pane)
    buffer = "fpp-#{pane}"
    tmux("capture-pane", "-J", "-S", "-", "-E", "-", "-b", buffer, "-t", pane)
    command = "tmux show-buffer -b #{Shellwords.escape(buffer)} | fpp; " \
      "tmux delete-buffer -b #{Shellwords.escape(buffer)}"
    tmux("display-popup", "-E", "-d", '#{pane_current_path}', "-w", "80%", "-h", "80%", command)
  end

  def run(arguments)
    command = arguments.shift
    case command
    when "metrics-loop" then metrics_loop(Integer(arguments.fetch(0, 60)))
    when "metrics" then update_metrics
    when "username" then puts username(*arguments.first(3))
    when "hostname" then puts hostname(*arguments.first(5))
    when "maximize" then maximize(*arguments.first(2))
    when "fpp" then fpp(arguments.first)
    else
      warn "unknown Oh My Tmux runtime command: #{command}"
      exit 64
    end
  end
end

OhMyTmuxRuntime.run(ARGV) if $PROGRAM_NAME == __FILE__
