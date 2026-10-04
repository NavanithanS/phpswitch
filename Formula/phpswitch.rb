class Phpswitch < Formula
  desc "PHP Version Manager for macOS"
  homepage "https://github.com/NavanithanS/phpswitch"
  url "https://github.com/NavanithanS/phpswitch/archive/refs/tags/v1.4.4.tar.gz"
  sha256 "66d0b3b9631ae12adc9b6b6511b0f3bc1268807d13b1b7270ea7fcb549607e25"
  license "MIT"

  def install
    bin.install "php-switcher.sh" => "phpswitch"
  end

  test do
    assert_match "PHPSwitch", shell_output("#{bin}/phpswitch --version")
  end
end
