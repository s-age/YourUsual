cask "your-usual" do
  version "1.0"
  sha256 "aa0ddde57220910a11bdcd709775ba83d0c1e1c12d63c597e923c1494c6ee11c"

  url "https://github.com/s-age/YourUsual/releases/download/v#{version}/YourUsual-#{version}.dmg"
  name "YourUsual"
  desc "Menu bar app for quick access to your usual files, directories, and commands"
  homepage "https://github.com/s-age/YourUsual"

  depends_on macos: :sequoia

  app "YourUsual.app"
  # Expose the bundled executable as the `your-usual` CLI (e.g. `your-usual cd <path>`).
  binary "#{appdir}/YourUsual.app/Contents/MacOS/YourUsual", target: "your-usual"

  zap trash: [
    "~/Library/Application Support/com.yourusual.app",
    "~/Library/Application Support/com.yourusual.app.dev",
    "~/Library/Preferences/com.yourusual.app.plist",
  ]
end
