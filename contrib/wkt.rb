# Draft formula for wmxscott/homebrew-tap. Fill in url and sha256 from the
# release tarball before copying it to Formula/wkt.rb.
class Wkt < Formula
  desc "Git worktrees, opened as tmux sessions or Herdr workspaces on request"
  homepage "https://github.com/wmxscott/wkt"
  url "https://github.com/wmxscott/wkt/archive/refs/tags/v2.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/wmxscott/wkt.git", branch: "main"

  uses_from_macos "git"
  uses_from_macos "zsh"

  def install
    bin.install "bin/wkt"
  end

  def caveats
    <<~EOS
      Running wkt with no arguments opens a picker. It needs fzf 0.36 or newer:
        brew install fzf
      To have the picker follow macOS's light and dark mode, install
      https://github.com/wmxscott/theme-monitor, or set WKT_THEME.
      Its icons need a Nerd Font in your terminal.
    EOS
  end

  test do
    assert_match "wkt #{version}", shell_output("#{bin}/wkt --version")
    assert_match "Usage: wkt <command>", shell_output("#{bin}/wkt --help")

    # Stand-in herdr, so the test never talks to a real Herdr session.
    (testpath/"stub/herdr").write <<~SH
      #!/bin/sh
      echo "$*" >> "#{testpath}/herdr.log"
    SH
    chmod 0755, testpath/"stub/herdr"
    ENV.prepend_path "PATH", testpath/"stub"

    ENV["GIT_AUTHOR_NAME"] = ENV["GIT_COMMITTER_NAME"] = "Test"
    ENV["GIT_AUTHOR_EMAIL"] = ENV["GIT_COMMITTER_EMAIL"] = "test@example.com"
    system "git", "init", "--quiet", "--initial-branch=main", "src"
    system "git", "-C", "src", "commit", "--quiet", "--allow-empty", "-m", "initial"
    system "git", "clone", "--quiet", "--bare", "src", "origin.git"

    mkdir "layout" do
      system bin/"wkt", "setup", testpath/"origin.git"
      cd "main" do
        refute_match "opened", shell_output("#{bin}/wkt new -b other")
        refute_path_exists testpath/"herdr.log"
        assert_match "opened in Herdr", shell_output("#{bin}/wkt new -b topic --herdr")
      end
    end
    assert_equal "other", shell_output("git -C #{testpath}/layout/other branch --show-current").chomp
    assert_equal "topic", shell_output("git -C #{testpath}/layout/topic branch --show-current").chomp
    assert_match "worktree open", (testpath/"herdr.log").read
  end
end
