class Phpswitch < Formula
  desc "PHP Version Manager for macOS"
  homepage "https://github.com/NavanithanS/phpswitch"
  url "https://github.com/NavanithanS/phpswitch/archive/refs/tags/v2.0.0.tar.gz"
  sha256 "9d4cbdb50a87cc1748c978507b97cd92b55c0b30f741992c273ecf14aa3d5f24"
  license "MIT"

  def install
    bin.install "php-switcher.sh" => "phpswitch"
    generate_completions_from_executable(bin/"phpswitch", "completions")
  end

  test do
    assert_match "PHPSwitch", shell_output("#{bin}/phpswitch --version")
  end
end
