require "spec_helper"
require "yaml"

describe "TensorBuzzPathFilter" do
  def config_file
    "tensorbuzz.yml"
  end

  def shared_paths
    ["Gemfile", "Gemfile.lock", "hayabusa.gemspec", ".ruby-version", config_file]
  end

  def builds
    @builds ||= YAML.load_file(File.expand_path("../#{config_file}", __dir__)).fetch("builds")
  end

  def glob_source(body)
    escaped = Regexp.escape(body)

    escaped.gsub("\\*\\*/", "(?:[^/]+/)*").gsub("\\*\\*", ".*").gsub("\\*", "[^/]*")
  end

  def glob(pattern)
    body = pattern.delete_prefix("!")
    source = glob_source(body)
    source = "(?:[^/]+/)*#{source}" unless body.include?("/")
    source = "#{source}(?:/.*)?" unless body.end_with?("*")

    Regexp.new("\\A#{source}\\z")
  end

  def compiled_rules(patterns)
    patterns.map do |pattern|
      {negated: pattern.start_with?("!"), glob: glob(pattern.delete_prefix("!"))}
    end
  end

  def decision(build, changed_paths)
    return "changed_paths_unavailable" if changed_paths.nil?
    return "config_file_changed" if changed_paths.include?(config_file)
    return "changed_paths_empty" if changed_paths.empty?

    rules = compiled_rules(build.fetch("paths"))
    matched = changed_paths.select do |path|
      last = rules.reverse.find { |rule| rule[:glob].match?(path) }
      last && !last[:negated]
    end

    matched.empty? ? "no_matching_path" : "matched_path"
  end

  it "declares paths on every build" do
    builds.each_value do |build|
      expect(build.fetch("paths")).to be_a(Array)
      expect(build.fetch("paths")).not_to be_empty
    end
  end

  it "keeps the fail-open base rule first so an unknown path can never skip a build" do
    builds.each_value do |build|
      expect(build.fetch("paths").first).to eq("**")
    end
  end

  it "rejects a negation with nothing after the bang" do
    builds.each_value do |build|
      build.fetch("paths").each do |pattern|
        next unless pattern.start_with?("!")

        expect(pattern.delete_prefix("!")).not_to be_empty
      end
    end
  end

  it "keeps every pattern inside the glob grammar this spec mirrors" do
    builds.each_value do |build|
      build.fetch("paths").each do |pattern|
        expect(pattern).not_to match(/[?\[\]]/)
      end
    end
  end

  it "never excludes the shared tooling every lane installs its bundle from" do
    builds.each_value do |build|
      negated = build.fetch("paths").select { |pattern| pattern.start_with?("!") }

      shared_paths.each do |path|
        expect(negated).not_to include(path)
      end
    end
  end

  it "runs every lane for a change to code all three read" do
    builds.each_value do |build|
      expect(decision(build, ["lib/hayabusa.rb"])).to eq("matched_path")
    end
  end

  it "skips every lane for a change no lane reads" do
    builds.each_value do |build|
      expect(decision(build, ["conf/apache2_hayabusa_conf.conf"])).to eq("no_matching_path")
    end
  end

  it "runs only the lint lane for a change to an executable the specs never load" do
    expect(decision(builds["build_1"], ["bin/hayabusa_fcgi.rb"])).to eq("no_matching_path")
    expect(decision(builds["build_3"], ["bin/hayabusa_fcgi.rb"])).to eq("matched_path")
  end

  it "runs the spec lanes for a template they render and not the lint lane" do
    expect(decision(builds["build_1"], ["pages/spec.rhtml"])).to eq("matched_path")
    expect(decision(builds["build_3"], ["pages/spec.rhtml"])).to eq("no_matching_path")
  end

  it "runs every lane when the config that declares paths changes" do
    builds.each_value do |build|
      expect(decision(build, [config_file, "lib/hayabusa.rb"])).to eq("config_file_changed")
    end
  end

  it "runs every lane when the changed-path list is empty or unavailable" do
    builds.each_value do |build|
      expect(decision(build, [])).to eq("changed_paths_empty")
      expect(decision(build, nil)).to eq("changed_paths_unavailable")
    end
  end
end
