# frozen_string_literal: true

require "optparse"
require "fileutils"
require "tempfile"
require "open3"
require_relative "arcana-dispatch"

module ArcanaSource
  class UsageError < StandardError; end
  Error = ArcanaDispatch::Error

  def self.help(command = nil)
    case command
    when "use"
      "Usage: arcana source use <dev|brew> <app>... | --all\n" \
        "Options: --all --dry-run --brew-prefix PATH (brew only) --dev-root PATH (dev only) -h --help\n"
    when "status", "doctor"
      "Usage: arcana source #{command}\nOptions: -h --help\n"
    else
      "Usage: arcana source <command>\n" \
        "  use <dev|brew> <app>... | --all   Select sources and provision stable launchers\n" \
        "  status                         Show selections and target health\n" \
        "  doctor                         Check bundles, launchers, and dispatcher health\n" \
        "Use arcana source <command> --help for options.\n"
    end
  end

  def self.absolute(value, label)
    raise UsageError, "#{label} must be an absolute path" unless value.is_a?(String) && value.start_with?("/")
    path = File.expand_path(value)
    raise UsageError, "invalid #{label}" unless ArcanaDispatch.absolute?(path)
    path
  end

  def self.registry(data)
    unless data.is_a?(Hash) && data.fetch("formulae", []).is_a?(Array) &&
           data.fetch("optional", {}).is_a?(Hash) &&
           data.fetch("optional", {}).fetch("formulae", []).is_a?(Array)
      raise Error, "invalid formula registry in tools.yaml"
    end
    entries = data.fetch("formulae", []) + data.fetch("optional", {}).fetch("formulae", [])
    apps = {}
    names = {}
    commands = {}
    entries.each do |item|
      raise Error, "invalid formula entry in tools.yaml" unless item.is_a?(Hash)
      next unless item.key?("sources")
      id = item["name"]
      source = item["sources"]
      unless ArcanaDispatch.name?(id) && id != "arcana" && source.is_a?(Hash) &&
             (source.keys - %w[commands aliases companions environment]).empty?
        raise Error, "invalid sources registration for #{id.inspect}"
      end
      public_commands = source["commands"]
      aliases = source.fetch("aliases", [])
      companions = source.fetch("companions", [])
      environment = source.fetch("environment", {})
      unless public_commands.is_a?(Array) && !public_commands.empty? && aliases.is_a?(Array) &&
             companions.is_a?(Array) && environment.is_a?(Hash)
        raise Error, "invalid sources bundle for #{id}"
      end
      ([id] + aliases).each do |name|
        raise Error, "invalid or duplicate source alias #{name.inspect}" unless ArcanaDispatch.name?(name) && !names.key?(name)
        names[name] = id
      end
      companion_commands = companions.map do |entry|
        unless entry.is_a?(Hash) && (entry.keys - %w[command platforms platform environment]).empty? &&
               ArcanaDispatch.name?(entry["command"]) &&
               (!entry.key?("environment") || (entry["environment"].is_a?(String) &&
                 /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(entry["environment"])))
          raise Error, "invalid companion for #{id}"
        end
        entry["command"]
      end
      bundle = public_commands + companion_commands
      unless bundle.all? { |name| ArcanaDispatch.name?(name) && name != "arcana" } && bundle.uniq == bundle
        raise Error, "invalid or duplicate commands for #{id}"
      end
      public_commands.each do |name|
        raise Error, "duplicate public source command #{name}" if commands.key?(name)
        commands[name] = id
      end
      unless environment.all? { |key, value| key.is_a?(String) && /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(key) && bundle.include?(value) }
        raise Error, "invalid source environment for #{id}"
      end
      installed = item["installed_name"] || id
      raise Error, "invalid installed_name for #{id}" unless ArcanaDispatch.name?(installed)
      active_entries = companions.select { |entry| platform_supported?(entry) }
      active_companions = active_entries.map { |entry| entry["command"] }
      environment = environment.dup
      active_entries.each do |entry|
        next unless entry.key?("environment")
        key = entry["environment"]
        raise Error, "duplicate source environment #{key} for #{id}" if environment.key?(key)
        environment[key] = entry["command"]
      end
      active_bundle = public_commands + active_companions
      unless environment.values.all? { |value| active_bundle.include?(value) } || !platform_supported?(item)
        raise Error, "source environment references unsupported companion for #{id}"
      end
      apps[id] = { "commands" => public_commands, "companions" => active_companions,
                   "environment" => environment, "installed_name" => installed,
                   "supported" => platform_supported?(item) }
    end
    [apps, names]
  end

  def self.present?(path)
    File.exist?(path) || File.symlink?(path)
  end

  def self.owned_file?(path, content, executable = false)
    File.file?(path) && !File.symlink?(path) && File.read(path) == content &&
      (!executable || File.executable?(path))
  end

  def self.publication_errors(files)
    files.each_with_object([]) do |(path, content, executable), errors|
      if present?(path) && !owned_file?(path, content, executable)
        errors << "refusing unmanaged or invalid file #{path} (move it aside manually)"
      end
      parent = File.dirname(path)
      parent = File.dirname(parent) until present?(parent)
      errors << "not a directory: #{parent}" unless File.directory?(parent)
    end
  end

  def self.report(state, apps, state_path)
    unhealthy = false
    (apps.keys + state["apps"].keys).uniq.sort.each do |id|
      app = state["apps"][id]
      unless app
        suffix = apps[id]["supported"] ? "" : " (unsupported platform)"
        puts "#{id}: unselected#{suffix}"
        next
      end
      puts "#{id}: #{app['source']}"
      errors = ArcanaDispatch.bundle_errors(state, id)
      errors.concat(ArcanaDispatch.runtime_errors(app["runtime"]))
      app["commands"].each do |command, target|
        launcher = app["launchers"].fetch(command)
        expected = ArcanaDispatch.wrapper(state_path, id, command, app["runtime"])
        health = if !present?(launcher)
                   "missing dispatcher"
                 elsif owned_file?(launcher, expected, true)
                   "dispatcher"
                 else
                   "invalid dispatcher"
                 end
        puts "  #{command} -> #{target} [#{health}]"
        errors << "#{command}: #{health} #{launcher}" unless health == "dispatcher"
      end
      app["companions"].each { |command, target| puts "  companion #{command} -> #{target}" }
      app["environment"].each { |key, target| puts "  #{key}=#{target} (unless explicitly set)" }
      errors.each { |error| puts "  ERROR: #{error}" }
      unhealthy ||= !errors.empty?
    end
    unhealthy ? 1 : 0
  end

  # Publish complete artifacts using atomic, no-clobber hard links. In particular,
  # an unlocked preflight must never see another writer's half-written runtime.
  # Only files made by this invocation are removed on ordinary publication failure.
  def self.publish(files, state, state_path)
    created = []
    temporary = nil
    begin
      files.each do |path, content, executable|
        next if owned_file?(path, content, executable)
        FileUtils.mkdir_p(File.dirname(path))
        file = Tempfile.new([".arcana-publish-", ".tmp"], File.dirname(path))
        begin
          file.chmod(executable ? 0o755 : 0o600)
          file.write(content)
          file.flush
          file.fsync
          File.link(file.path, path)
          created << [path, file.stat.dev, file.stat.ino]
        ensure
          file.close!
        end
      end
      temporary = Tempfile.new([".sources-", ".json"], File.dirname(state_path))
      temporary.chmod(0o600)
      temporary.write(JSON.pretty_generate(state) + "\n")
      temporary.flush
      temporary.fsync
      File.rename(temporary.path, state_path)
    rescue StandardError
      created.reverse_each do |path, dev, ino|
        begin
          stat = File.lstat(path)
          File.unlink(path) if stat.dev == dev && stat.ino == ino
        rescue SystemCallError
          # Never remove a replacement file, or mask the original error.
        end
      end
      raise
    ensure
      temporary.close! if temporary
    end
  end

  def self.run(argv)
    command = argv.shift
    if %w[-h --help].include?(command)
      raise UsageError, "unexpected arguments" unless argv.empty?
      puts help
      return 0
    end
    raise UsageError, help unless %w[use status doctor].include?(command)
    options = {}
    parser = OptionParser.new do |opts|
      if command == "use"
        opts.on("--all") { options[:all] = true }
        opts.on("--dry-run") { options[:dry_run] = true }
        opts.on("--brew-prefix PATH") { |value| options[:brew_prefix] = absolute(value, "brew prefix") }
        opts.on("--dev-root PATH") { |value| options[:dev_root] = absolute(value, "dev root") }
      end
      opts.on("-h", "--help") { options[:help] = true }
    end
    # Reject OptionParser's normally accepted long-option abbreviations.
    allowed = %w[--help]
    allowed += %w[--all --dry-run --brew-prefix --dev-root] if command == "use"
    argv.each do |arg|
      if arg.start_with?("--") && arg != "--" && !allowed.include?(arg.split("=", 2).first)
        raise UsageError, "invalid option: #{arg}"
      end
    end
    parser.parse!(argv)
    if options[:help]
      puts help(command)
      return 0
    end
    home = File.expand_path("~")
    state_home = absolute(ENV.fetch("XDG_STATE_HOME", File.join(home, ".local/state")), "XDG_STATE_HOME")
    state_path = File.join(state_home, "arcana", "sources.json")
    bin = absolute(ENV.fetch("ARCANA_BIN_DIR", File.join(home, ".local/bin")), "ARCANA_BIN_DIR")
    apps, names = registry(manifest)
    if command != "use"
      raise UsageError, "unexpected arguments for #{command}" unless argv.empty?
      return report(ArcanaDispatch.read_state(state_path), apps, state_path)
    end
    source = argv.shift
    raise UsageError, "expected source dev or brew" unless %w[dev brew].include?(source)
    raise UsageError, "--all cannot be combined with app names" if options[:all] && !argv.empty?
    raise UsageError, "select app names or --all" if !options[:all] && argv.empty?
    if (source == "dev" && options[:brew_prefix]) || (source == "brew" && options[:dev_root])
      raise UsageError, "root option does not match selected source"
    end
    selected = if options[:all]
                 apps.keys.select { |id| apps[id]["supported"] }
               else
                 argv.map do |name|
                   id = names[name]
                   raise UsageError, "unknown source app #{name}" unless id
                   raise UsageError, "unsupported source app #{name} on #{current_platform}" unless apps[id]["supported"]
                   id
                 end.uniq
               end
    raise UsageError, "empty source selection" if selected.empty?
    # Validate existing state even before consulting Homebrew.
    ArcanaDispatch.read_state(state_path)
    root = if source == "dev"
             options[:dev_root] || File.join(home, ".local/libexec/arcana-dev")
           elsif options[:brew_prefix]
             options[:brew_prefix]
           else
             output, status = Open3.capture2("brew", "--prefix", err: File::NULL)
             raise Error, "brew --prefix failed; provide --brew-prefix PATH" unless status.success?
             absolute(output.strip, "brew prefix")
           end
    runtime_content = File.read(File.join(__dir__, "arcana-dispatch.rb"))
    runtime = File.join(File.dirname(state_path), "dispatch-v1-#{Digest::SHA256.hexdigest(runtime_content)}.rb")
    prepare = lambda do
      state = ArcanaDispatch.read_state(state_path)
      files = [[runtime, runtime_content, false]]
      selected.each do |id|
        registration = apps.fetch(id)
        payload = source == "dev" ? File.join(root, id, "bin") : File.join(root, "opt", registration["installed_name"], "bin")
        targets = {}
        (registration["commands"] + registration["companions"]).each { |cmd| targets[cmd] = File.join(payload, cmd) }
        app = { "source" => source, "runtime" => runtime, "commands" => {}, "companions" => {},
                "launchers" => {}, "environment" => {} }
        %w[commands companions].each { |key| registration[key].each { |cmd| app[key][cmd] = targets.fetch(cmd) } }
        registration["environment"].each { |key, cmd| app["environment"][key] = targets.fetch(cmd) }
        registration["commands"].each do |cmd|
          launcher = File.join(bin, cmd)
          app["launchers"][cmd] = launcher
          files << [launcher, ArcanaDispatch.wrapper(state_path, id, cmd, runtime), true]
        end
        state["apps"][id] = app
      end
      errors = publication_errors(files)
      selected.each { |id| errors.concat(ArcanaDispatch.bundle_errors(state, id)) }
      owners = {}
      state["apps"].each do |id, app|
        app["commands"].each_key do |cmd|
          errors << "command #{cmd} already registered to #{owners[cmd]}" if owners.key?(cmd)
          owners[cmd] = id
        end
      end
      raise Error, errors.join("\n") unless errors.empty?
      [state, files]
    end
    if options[:dry_run]
      prepare.call
    else
      # Do all read-only preflight first, then repeat under the writer lock.
      prepare.call
      FileUtils.mkdir_p(File.dirname(state_path))
      lock_path = File.join(File.dirname(state_path), "sources.lock")
      raise Error, "invalid source lock #{lock_path}" if File.symlink?(lock_path) || (present?(lock_path) && !File.file?(lock_path))
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        state, files = prepare.call
        publish(files, state, state_path)
      end
    end
    puts "#{options[:dry_run] ? 'Would select' : 'Selected'} #{source} for #{selected.join(', ')}. Applies to new launches only."
    0
  rescue UsageError, OptionParser::ParseError => e
    warn "arcana source: #{e.message}"
    2
  rescue Error, SystemCallError, IOError, Psych::Exception => e
    warn "arcana source: #{e.message}"
    1
  end
end
