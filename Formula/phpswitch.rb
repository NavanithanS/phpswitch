class Phpswitch < Formula
  desc "PHP Version Manager for macOS"
  homepage "https://github.com/NavanithanS/phpswitch"
  url "https://github.com/NavanithanS/phpswitch/archive/refs/tags/v1.4.3.tar.gz"
  sha256 "c06eff899eb3c1b18b25a12e1eb8025ed8454e8898d35c98cf6de8a0d5dc926b"
  license "MIT"

  def install
    bin.install "php-switcher.sh" => "phpswitch"
  end

  test do
    assert_match "PHPSwitch", shell_output("#{bin}/phpswitch --version")
  end
end
