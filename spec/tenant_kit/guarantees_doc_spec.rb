require "spec_helper"

# docs/GUARANTEES.md links every guarantee to a spec line. Fail if a link
# drifts off its example, so the document can't silently rot.
RSpec.describe "docs/GUARANTEES.md" do
  root = File.expand_path("../..", __dir__)
  links = File.read(File.join(root, "docs/GUARANTEES.md")).scan(%r{\(\.\./(spec/[\w/]+\.rb)#L(\d+)\)}).uniq

  it "links to spec examples" do
    expect(links.size).to be > 40
  end

  links.each do |path, line|
    it "#{path}:#{line} is an example" do
      source = File.readlines(File.join(root, path))[Integer(line) - 1].to_s
      expect(source).to match(/^\s*it "/)
    end
  end
end
