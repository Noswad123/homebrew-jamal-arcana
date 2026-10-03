class Djinn < Formula
  desc "Local-first companion for OpenCode and other AI coding agents"
  homepage "https://github.com/Noswad123/djinn"
  url "https://github.com/Noswad123/djinn.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"
  revision 1

  depends_on "bun" => :build
  depends_on "rust" => :build

  def install
    patch_djinn_ui_prompt_environment!

    system "cargo", "install", *std_cargo_args(path: "crates/djinn-cli")
    system "make", "install-ui", "INSTALL_DIR=#{bin}"

    libexec.install bin/"djinn" => "djinn"
    (bin/"djinn").write_env_script libexec/"djinn", DJINN_UI_BIN: opt_bin/"djinn-ui"
  end

  test do
    assert_match "Local-first companion", shell_output("#{bin}/djinn --help")
    system bin/"djinn-ui", "--version"
  end

  def patch_djinn_ui_prompt_environment!
    # The current Djinn UI source can crash while sending prompts because the
    # legacy prompt path boots the full v2 location-service graph only to render
    # project references. Keep the formula installable on fresh Linux machines
    # until this lands upstream in the Djinn repo.
    inreplace "clients/djinn-ui/packages/opencode/src/session/system.ts" do |s|
      s.gsub! <<~TS, ""
        import { AbsolutePath } from "@opencode-ai/core/schema"
        import { Location } from "@opencode-ai/core/location"
        import { LocationServiceMap, locationServiceMapLayer } from "@opencode-ai/core/location-services"
        import { Reference } from "@opencode-ai/core/reference"
      TS

      s.gsub! "    const locations = yield* LocationServiceMap.Service\n\n", ""

      old_context = <<~TS.gsub(/^/, "        ").chomp
        const ctx = yield* InstanceState.context
        const references = yield* Effect.gen(function* () {
          return (yield* (yield* Reference.Service).list()).filter((reference) => reference.description !== undefined)
        }).pipe(Effect.provide(locations.get(Location.Ref.make({ directory: AbsolutePath.make(ctx.directory) }))))
      TS
      new_context = <<~TS.gsub(/^/, "        ").chomp
        const ctx = yield* InstanceState.context
        // Keep the legacy TUI prompt path focused on basic environment metadata.
        // The current Djinn UI build fails while booting the full v2 location
        // service graph just to render project references, surfacing to users as
        // "failed to send prompt". The v2 runner still owns dynamic reference
        // guidance; this path should not block prompt sending on that graph.
      TS
      s.gsub! old_context, new_context

      old_references = <<~TS.gsub(/^/, "          ")
        references.length === 0
          ? undefined
          : [
              "Project references provide additional directories that can be accessed when relevant.",
              "<available_references>",
              ...references
                .toSorted((a, b) => a.name.localeCompare(b.name))
                .flatMap((reference) => [
                  "  <reference>",
                  `    <name>${reference.name}</name>`,
                  `    <path>${reference.path}</path>`,
                  ...(reference.description === undefined
                    ? []
                    : [`    <description>${reference.description}</description>`]),
                  "  </reference>",
                ]),
              "</available_references>",
            ].join("\\n"),
      TS
      s.gsub! old_references, ""
      s.gsub! "].filter((part): part is string => part !== undefined)", "]"

      s.gsub! <<~TS, ""
        const locationServiceMapNode = LayerNode.make({
          service: LocationServiceMap.Service,
          layer: locationServiceMapLayer,
          deps: [],
        })

      TS

      s.gsub! "deps: [Skill.node, MCP.node, locationServiceMapNode]", "deps: [Skill.node, MCP.node]"
    end
  end
end
