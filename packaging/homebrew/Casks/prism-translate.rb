# Cask do Prism Translate.
# Publicar em https://github.com/GoobinEXE/homebrew-tap (Casks/prism-translate.rb).
# Instalação: brew tap goobinexe/tap && brew trust --tap goobinexe/tap && brew install --cask prism-translate
# O zip vem de `./scripts/release.sh --homebrew` (Developer ID + notarização), que atualiza version e sha256.

cask "prism-translate" do
  version "1.1.1"
  sha256 "3aa134b0810303d534a3b9ed2e28696025fb0aa543f9cc9f6c1415378e547060"

  url "https://github.com/GoobinEXE/PrismTranslate/releases/download/v#{version}/Prism-#{version}.zip"
  name "Prism Translate"
  desc "Tradutor do texto do campo focado, na barra de menus"
  homepage "https://github.com/GoobinEXE/PrismTranslate"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Prism.app"

  zap trash: [
    "~/Library/Application Support/Prism",
    "~/Library/Preferences/com.marcelopessoa.prism.plist",
    "~/Library/Preferences/dev.prism.tradutor.plist",
  ]

  caveats <<~EOS
    O Prism precisa de Acessibilidade e Monitoramento de Entrada para funcionar.
    Conceda em Ajustes do Sistema → Privacidade e Segurança na primeira abertura.
  EOS
end
