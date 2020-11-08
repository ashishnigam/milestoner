# frozen_string_literal: true

require "spec_helper"

RSpec.describe Milestoner::Tagger, :temp_dir, :git_repo do
  using Refinements::Pathnames

  subject(:tagger) { described_class.new commit_prefixes: %w[Fixed Added Updated Removed] }

  let(:version) { Versionaire::Version "0.1.0" }

  let :tag_details do
    ->(version) { Open3.capture2(%(git show --stat --pretty=format:"%b" #{version})).first }
  end

  describe "#initialize" do
    subject(:tagger) { described_class.new }

    it "answers nil version" do
      expect(tagger.version).to eq(nil)
    end

    it "answers commit prefixes" do
      expect(tagger.commit_prefixes).to eq([])
    end
  end

  describe "#commit_prefix_regex" do
    context "with prefixes" do
      it "answers regex for for commit prefixes" do
        expect(tagger.commit_prefix_regex).to eq(/Fixed|Added|Updated|Removed/)
      end
    end

    context "without prefixes" do
      subject(:tagger) { described_class.new commit_prefixes: [] }

      it "answers empty regex" do
        expect(tagger.commit_prefix_regex).to eq(//)
      end
    end
  end

  describe "#commits" do
    it "answers commits since last tag when tagged" do
      git_repo_dir.change_dir do
        `git tag v0.0.0`
        `git rm one.txt`
        `git commit --all --message "Removed one.txt"`

        commits = tagger.commits.map(&:subject)

        expect(commits).to contain_exactly("Removed one.txt")
      end
    end

    it "answers all commits when not tagged" do
      git_repo_dir.change_dir do
        commits = tagger.commits.map(&:subject)
        expect(commits).to contain_exactly("Added dummy files")
      end
    end

    context "with prefixed commits" do
      before do
        git_repo_dir.change_dir do
          `touch a.txt && git add --all && git commit --message "This is not a good commit message"`
          `touch b.txt && git add --all && git commit --message "Updated gem dependencies"`
          `touch c.txt && git add --all && git commit --message "Fixed README typos"`
          `touch d.txt && git add --all && git commit --message "Updated version release notes"`
          `touch e.txt && git add --all && git commit --message "Removed unused stylesheets"`
          `touch g.txt && git add --all && git commit --message "Refactored authorization"`
        end
      end

      let :expectation do
        [
          "Fixed README typos",
          "Added dummy files",
          "Updated gem dependencies",
          "Updated version release notes",
          "Removed unused stylesheets",
          "Refactored authorization",
          "This is not a good commit message"
        ]
      end

      it "answers commits grouped by prefix and alpha-sorted per group" do
        git_repo_dir.change_dir do
          commits = tagger.commits.map(&:subject)
          expect(commits).to eq(expectation)
        end
      end
    end

    context "with prefixed commits using special characters" do
      subject(:tagger) { described_class.new commit_prefixes: ["[one]", "=+-#", "with spaces"] }

      before do
        git_repo_dir.change_dir do
          `touch a.txt && git add --all && git commit --message "Apple"`
          `touch b.txt && git add --all && git commit --message "with spaces"`
          `touch c.txt && git add --all && git commit --message "=+-#"`
          `touch d.txt && git add --all && git commit --message "[one] more"`
        end
      end

      it "answers commits grouped by prefix and alpha-sorted per group" do
        git_repo_dir.change_dir do
          commits = tagger.commits.map(&:subject)
          expect(commits).to eq(["[one] more", "=+-#", "with spaces", "Added dummy files", "Apple"])
        end
      end
    end

    context "without prefixed commits" do
      let(:prefixes) { [] }

      before do
        git_repo_dir.change_dir do
          `touch a.txt && git add --all && git commit --message "One"`
          `touch b.txt && git add --all && git commit --message "Two"`
        end
      end

      it "answers alphabetically sorted commits" do
        git_repo_dir.change_dir do
          commits = tagger.commits.map(&:subject)
          expect(commits).to eq(["Added dummy files", "One", "Two"])
        end
      end
    end

    context "with duplicate commit messages" do
      before do
        git_repo_dir.change_dir do
          `touch a.txt && git add --all && git commit --message "Updated gem dependencies"`
          `touch b.txt && git add --all && git commit --message "Updated gem dependencies"`
        end
      end

      it "answers commits with duplicates removed" do
        git_repo_dir.change_dir do
          commits = tagger.commits.map(&:subject)
          expect(commits).to eq(["Added dummy files", "Updated gem dependencies"])
        end
      end
    end
  end

  describe "#commit_list" do
    before do
      git_repo_dir.change_dir do
        `touch a.txt && git add --all && git commit --message "One"`
        `touch b.txt && git add --all && git commit --message "Two"`
      end
    end

    it "answers a formatted list of commit messages" do
      git_repo_dir.change_dir do
        expect(tagger.commit_list).to contain_exactly(
          "- Added dummy files - Test Example",
          "- One - Test Example",
          "- Two - Test Example"
        )
      end
    end
  end

  describe "#create" do
    it "creates default tag" do
      git_repo_dir.change_dir do
        tagger.create version
        expect(tag_details.call("0.1.0")).to match(/tag\s0\.1\.0/)
      end
    end

    it "creates custom tag" do
      git_repo_dir.change_dir do
        tagger.create "0.2.0"
        expect(tag_details.call("0.2.0")).to match(/tag\s0\.2\.0/)
      end
    end

    it "creates tag message" do
      git_repo_dir.change_dir do
        tagger.create version
        expect(tag_details.call("0.1.0")).to match(/Version\s0\.1\.0/)
      end
    end

    # rubocop:disable RSpec/ExampleLength
    it "creates tag message with commits since last tag" do
      git_repo_dir.change_dir do
        `git rm one.txt`
        `git commit --all --message "Removed one"`

        `printf "Test" > two.txt`
        `git commit --all --message "Updated two"`

        `printf "Three." > three.txt`
        `git commit --all --message "Fixed three"`

        tagger.create version

        expect(tag_details.call("0.1.0")).to match(/
          Version\s0\.1\.0\n\n
          -\sFixed\sthree\s-\sTest\sExample\n
          -\sAdded\sdummy\sfiles\s-\sTest\sExample\n
          -\sUpdated\stwo\s-\sTest\sExample\n
          -\sRemoved\sone\s-\sTest\sExample\n\n\n\n
        /x)
      end
    end
    # rubocop:enable RSpec/ExampleLength

    it "does not execute backticks in commit subject when adding tag message" do
      git_repo_dir.change_dir do
        `printf "Test" > two.txt`
        %x(git commit --all --message 'Updated two.txt with \`bogus command\` in message')

        tagger.create version

        expect(tag_details.call("0.1.0")).to match(/
          Version\s0\.1\.0\n\n
          -\sAdded\sdummy\sfiles\s-\sTest\sExample\n
          -\sUpdated\stwo\.txt\swith\s`bogus\scommand`\sin\smessage\s-\sTest\sExample\n\n\n\n
        /x)
      end
    end

    context "when not signed" do
      it "does not sign tag" do
        git_repo_dir.change_dir do
          tagger.create version
          expect(tag_details.call("0.1.0")).not_to match(/-{5}BEGIN\sPGP\sSIGNATURE-{5}/)
        end
      end
    end

    context "when signed" do
      let(:gpg_dir) { File.join temp_dir, ".gnupg" }
      let(:gpg_script) { File.join temp_dir, "..", "..", "spec", "support", "gpg_script" }
      let :gpg_key do
        `gpg --list-secret-keys #{git_user_email} | grep "[A-F0-9]$" | tr -d ' '`.chomp
      end

      # rubocop:disable RSpec/ExampleLength
      it "signs tag" do
        skip "Needs non-interactive support for local and remote builds" do
          ClimateControl.modify GNUPGHOME: gpg_dir do
            git_repo_dir.change_dir do
              gpg_dir.make_dir.chmod 0o700
              `gpg --batch --generate-key --quiet --gen-key #{gpg_script}`
              `git config --local user.signingkey #{gpg_key}`
              tagger.create version, sign: true

              expect(tag_details.call("0.1.0")).to match(/-{5}BEGIN\sPGP\sSIGNATURE-{5}/)
            end
          end
        end
      end
      # rubocop:enable RSpec/ExampleLength
    end

    it "prints warning with existing tag" do
      git_repo_dir.change_dir do
        tagger.create version
        result = -> { tagger.create version }

        expect(&result).to output(/warn.+Local\stag.+0\.1\.0.+/).to_stdout
      end
    end

    it "doesn't print warning without existing tag" do
      git_repo_dir.change_dir do
        result = -> { tagger.create version }
        expect(&result).not_to output(/warn.+Local\stag.+0\.1\.0.+/).to_stdout
      end
    end

    context "when GPG program is missing" do
      it "signs tag" do
        git_repo_dir.change_dir do
          `git config --local gpg.program /dev/null`
          result = -> { tagger.create version, sign: true }

          expect(&result).to raise_error(Milestoner::Errors::Git, "Unable to create tag: 0.1.0.")
        end
      end
    end

    it "fails with no Git commits" do
      temp_dir.change_dir do
        `git init`
        result = proc { tagger.create version }

        expect(&result).to raise_error(Milestoner::Errors::Git, "Unable to tag without commits.")
      end
    end

    it "fails with invalid version" do
      result = -> { tagger.create "bogus" }
      expect(&result).to raise_error(Versionaire::Errors::Conversion)
    end
  end
end
