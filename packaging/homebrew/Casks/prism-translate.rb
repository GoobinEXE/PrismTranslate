# Cask do Prism Translate (Community).
# Publicar em https://github.com/GoobinEXE/homebrew-tap (Casks/prism-translate.rb).
# Instalação: brew tap goobinexe/tap && brew trust --tap goobinexe/tap && brew install --cask prism-translate
# Futuro (homebrew-cask oficial): brew install --cask prism-translate

cask "prism-translate" do
  version "1.0.10"
  sha256 "1a2ec666a602cb49357fafa8f4c01daf8ec2ddf4ad3f553913ea9072d78bb1b5"

  url "https://github.com/GoobinEXE/PrismTranslate/releases/download/v#{version}/Prism-#{version}.zip"
  name "Prism Translate"
  desc "Traduz o texto do campo focado na barra de menus do Mac"
  homepage "https://github.com/GoobinEXE/PrismTranslate"

  depends_on macos: :sequoia

  app "Prism.app"

  zap trash: [
    "~/Library/Preferences/com.marcelopessoa.prism.plist",
    "~/Library/Application Support/Prism",
  ]

  caveats <<~EOS
    Na primeira abertura o macOS pode avisar que o app não foi verificado pela Apple.
    Vá em Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim.

    O Prism precisa de Acessibilidade e Monitoramento de Entrada para funcionar.
  EOS
end
