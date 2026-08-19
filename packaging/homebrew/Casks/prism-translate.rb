# Cask do Prism Translate (Community).
# Publicar em https://github.com/GoobinEXE/homebrew-tap (Casks/prism-translate.rb).
# Instalação: brew tap goobinexe/tap && brew trust --tap goobinexe/tap && brew install --cask prism-translate
# Futuro (homebrew-cask oficial): brew install --cask prism-translate

cask "prism-translate" do
  version "1.0.5"
  sha256 "4d18976834019b3991668ec770d82fcc33643e0a3786a061bf6e643a7c62b139"

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
