class Phpswitch < Formula
  desc "PHP Version Manager for macOS"
  homepage "https://github.com/NavanithanS/phpswitch"
  url "https://github.com/NavanithanS/phpswitch/archive/refs/tags/v1.4.5.tar.gz"
  sha256 "TODO_CALCULATE_AFTER_RELEASE_TAG" # Run: curl -sL <url> | shasum -a 256
  license "MIT"

  def install
    bin.install "php-switcher.sh" => "phpswitch"
  end

  test do
    assert_match "PHPSwitch", shell_output("#{bin}/phpswitch --version")
  end
end
