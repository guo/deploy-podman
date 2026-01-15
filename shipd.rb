class Shipd < Formula
  desc "Container deployment automation tool for Docker and Podman"
  homepage "https://github.com/guo/shipd"
  url "https://github.com/guo/shipd/archive/refs/tags/v1.0.3.tar.gz"
  sha256 "bf88cc8eb3f2b84491ee38064c8bbaa3a21da6fd16a46899efde727fcad0a548"
  license "MIT"

  def install
    # Install main executable
    bin.install "shipd.sh" => "shipd"

    # Install library files
    libexec.install Dir["lib/*.sh"]

    # Create symlinks for lib files to expected location
    (lib/"shipd").mkpath
    Dir[libexec/"*.sh"].each do |lib_file|
      (lib/"shipd"/File.basename(lib_file)).make_symlink(lib_file)
    end
  end

  def caveats
    <<~EOS
      Shipd has been installed!

      Targets search order:
        1. ./targets/ (current directory)
        2. ~/.shipd/targets/ (home directory)

      Quick start:
        # Create a target
        mkdir -p ~/.shipd/targets/myapp

        # Configure and deploy
        shipd deploy myapp

      Documentation: #{homepage}
    EOS
  end

  test do
    system "#{bin}/shipd", "--version"
  end
end
