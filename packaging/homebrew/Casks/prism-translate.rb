# Cask do Prism Translate (Community).
# Publicar em https://github.com/GoobinEXE/homebrew-tap (Casks/prism-translate.rb).
# Instalação: brew tap goobinexe/tap && brew trust --tap goobinexe/tap && brew install --cask prism-translate
# Futuro (homebrew-cask oficial): brew install --cask prism-translate

cask "prism-translate" do
  version "1.0.3"
  sha256 "d2502dbbfce6fc512353fc898a34d7eb5364b5708663f31098db18ddbcb058de"

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
