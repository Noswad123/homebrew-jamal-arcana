# frozen_string_literal: true

require "json"
require "digest"

# This file is copied intact into user state; dispatch never needs the tap.
module ArcanaDispatch
  class Error < StandardError; end
  NAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]*(?:\.[a-zA-Z0-9_-]+)*\z/
  MARKER = "# arcana-source-launcher-v1"

  def self.name?(value)
    value.is_a?(String) && NAME.match?(value)
  end

  def self.absolute?(value)
    value.is_a?(String) && value.start_with?("/") && !value.include?("\0") &&
      !value.include?("\n") && File.expand_path(value) == value
  end

  def self.keys!(value, keys, label)
    raise Error, "invalid #{label}" unless value.is_a?(Hash) && value.keys.sort == keys.sort
  end

  def self.paths!(value, label)
    unless value.is_a?(Hash) && value.all? { |key, path| name?(key) && absolute?(path) }
      raise Error, "invalid #{label}"
    end
  end

  def self.read_state(path)
    return { "version" => 1, "apps" => {} } unless File.exist?(path) || File.symlink?(path)

    raise Error, "state must be a regular file: #{path}" unless File.file?(path) && !File.symlink?(path)
    state = JSON.parse(File.read(path))
    keys!(state, %w[version apps], "source state")
    unless state["version"].is_a?(Integer) && state["version"] == 1
      raise Error, "unsupported source state version"
    end
    raise Error, "invalid apps in source state" unless state["apps"].is_a?(Hash)
    commands = []
    launchers = []
    state["apps"].each do |id, app|
      raise Error, "invalid source app id" unless name?(id) && id != "arcana"
      keys!(app, %w[source commands companions environment launchers runtime], "registration for #{id}")
      raise Error, "invalid source for #{id}" unless %w[dev brew].include?(app["source"])
      %w[commands companions launchers].each { |key| paths!(app[key], "#{key} for #{id}") }
      if app["commands"].empty? || app["commands"].keys.sort != app["launchers"].keys.sort ||
         !(app["commands"].keys & app["companions"].keys).empty? || app["commands"].key?("arcana")
        raise Error, "invalid command bundle for #{id}"
      end
      env = app["environment"]
      targets = app["commands"].values + app["companions"].values
      unless env.is_a?(Hash) && env.all? { |key, value| key.is_a?(String) && /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(key) && targets.include?(value) }
        raise Error, "invalid environment for #{id}"
      end
      raise Error, "invalid runtime for #{id}" unless absolute?(app["runtime"])
      commands.concat(app["commands"].keys)
      launchers.concat(app["launchers"].values)
    end
    if commands.uniq != commands || launchers.uniq != launchers
      raise Error, "duplicate commands or launchers in source state"
    end
    state
  rescue JSON::ParserError => e
    raise Error, "invalid source state JSON: #{e.message}"
  end

  def self.interpreter
    require "rbconfig"
    ruby = RbConfig.ruby
    # Do not freeze a Homebrew Ruby Cellar version into durable launchers.
    stable = ruby.sub(%r{/Cellar/([^/]+)/[^/]+/}, '/opt/\1/')
    if stable != ruby && File.executable?(stable) && File.identical?(ruby, stable)
      stable
    elsif File.executable?("/usr/bin/ruby") && File.identical?(ruby, "/usr/bin/ruby")
      "/usr/bin/ruby"
    else
      ruby
    end
  end

  def self.wrapper(state_path, id, command, _runtime)
    # The launcher is stable across dispatcher upgrades. The atomic selection
    # chooses the content-addressed runtime as well as the payload.
    <<~RUBY
      #!#{interpreter} --disable=gems
      #{MARKER}
      require "digest"
      require "json"
      begin
        state_path = #{state_path.dump}
        state = JSON.parse(File.read(state_path))
        unless state.is_a?(Hash) && state["apps"].is_a?(Hash) && state["apps"][#{id.dump}].is_a?(Hash)
          raise LoadError, "missing or invalid Arcana source registration"
        end
        runtime = state["apps"][#{id.dump}]["runtime"]
        unless runtime.is_a?(String) && runtime.start_with?("/") && !runtime.include?("\\0")
          raise LoadError, "invalid Arcana dispatcher path"
        end
        expected = /\\Adispatch-v1-([a-f0-9]{64})\\.rb\\z/.match(File.basename(runtime))
        unless expected && File.file?(runtime) && !File.symlink?(runtime) && Digest::SHA256.file(runtime).hexdigest == expected[1]
          raise LoadError, "missing or invalid Arcana dispatcher: " + runtime
        end
        require runtime
        ArcanaDispatch.run(state_path, #{id.dump}, #{command.dump}, __FILE__)
      rescue JSON::ParserError => e
        warn "arcana source: invalid source state JSON: " + e.message + "\\nRun arcana source doctor to inspect the state."
        exit 1
      rescue LoadError, SystemCallError, IOError => e
        warn "arcana source: " + e.message + "\\nRun arcana source doctor and reselect the app to repair."
        exit 1
      end
    RUBY
  end

  def self.runtime_errors(path)
    expected = /\Adispatch-v1-([a-f0-9]{64})\.rb\z/.match(File.basename(path))
    return ["invalid dispatcher #{path}"] unless expected && File.file?(path) && !File.symlink?(path)
    return ["invalid dispatcher digest #{path}"] unless Digest::SHA256.file(path).hexdigest == expected[1]

    []
  end

  def self.bundle_errors(state, id, launcher = nil)
    app = state.fetch("apps").fetch(id)
    forbidden = state["apps"].values.flat_map { |entry| entry["launchers"].values + [entry["runtime"]] }
    forbidden << launcher if launcher
    errors = []
    app["commands"].merge(app["companions"]).each do |command, target|
      unless File.file?(target) && File.executable?(target)
        errors << "#{id}/#{command}: missing or non-executable target #{target}"
        next
      end
      recursive = forbidden.any? { |path| File.exist?(path) && File.identical?(target, path) }
      recursive ||= File.open(target, "rb") { |file| (file.read(4096) || "").include?(MARKER) }
      errors << "#{id}/#{command}: recursive dispatcher target #{target}" if recursive
    end
    errors
  end

  def self.run(state_path, id, command, launcher)
    state = read_state(state_path)
    app = state["apps"][id]
    raise Error, "#{id} is unselected" unless app && app["commands"].key?(command)
    errors = bundle_errors(state, id, launcher)
    raise Error, errors.join("\n") unless errors.empty?

    environment = app["environment"].reject { |key, _value| ENV.key?(key) }
    target = app["commands"].fetch(command)
    exec(environment, [target, command], *ARGV)
  rescue Error, SystemCallError, IOError => e
    warn "arcana source: #{e.message}\nRun arcana source doctor, then arcana source use <dev|brew> #{id} to repair."
    exit 1
  end
end
