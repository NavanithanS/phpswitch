class Phpswitch < Formula
  desc "PHP Version Manager for macOS"
  homepage "https://github.com/NavanithanS/phpswitch"
  url "https://github.com/NavanithanS/phpswitch/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  def install
    bin.install "php-switcher.sh" => "phpswitch"
  end

  test do
    assert_match "PHPSwitch", shell_output("#{bin}/phpswitch --version")
  end
end
