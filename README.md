# Prosa Silk — app iOS

Empacota o site publicado como app iOS instalável. O app abre a URL definida em
`capacitor.config.json` (`server.url`) dentro de um WebView nativo.

- nome exibido: **Prosa Silk**
- bundle id: `com.prosasilk.app`
- URL carregada: `https://alma-conversation-garden.lovable.app`
- wrapper: Capacitor 7 (iOS)
- mínimo: iOS 14.0

## Como sai o IPA

Não dá pra compilar IPA no Windows — precisa de macOS/Xcode. Por isso o build roda no
GitHub Actions (runner `macos-latest`):

1. `npm install`
2. `npx cap add ios` + `npx cap sync ios`
3. aplica os patches de marca (ver abaixo)
4. `xcodebuild` gera um `.app` **sem assinatura**
5. empacota em `Payload/` → `app.ipa`
6. sobe o `app.ipa` como **artifact** do workflow

Dispara sozinho a cada push em `main`, ou manual em **Actions → build-ipa → Run workflow**.

## Patches de marca (aplicados no CI depois do `cap sync`)

| arquivo no repo | destino no projeto gerado | o que faz |
|---|---|---|
| `ios-assets/AppIcon-512@2x.png` | `AppIcon.appiconset/` | ícone do app (o logo da Prosa) |
| `ios-assets/splash-2732x2732*.png` | `Splash.imageset/` | tela de abertura |
| `ios-patches/AppDelegate.swift` | `App/App/AppDelegate.swift` | registra o `WKUserScript` que remove qualquer marca de terceiro do site |
| `ios-patches/Main.storyboard` | `App/App/Base.lproj/Main.storyboard` | aponta a cena pro `ViewController` local |

O `ViewController` (declarado dentro do próprio `AppDelegate.swift`, pra não precisar
mexer no `.xcodeproj`) sobrescreve `capacitorDidLoad()` e injeta um `<style>` com
`injectionTime: .atDocumentStart` — isso roda antes de o WebView carregar a URL, então
a plaquinha do hospedeiro do site nasce já escondida, sem piscar.

## Instalar no iPhone

1. Aba **Actions** → último run verde → baixa o artifact **app-ipa**.
2. Extrai o zip → fica o `app.ipa`.
3. **Sideloadly** no PC, iPhone plugado, arrasta o `app.ipa`, põe teu Apple ID.
4. Start. O Sideloadly assina na hora.

> App ID grátis expira em 7 dias — reassina quando pedir.

## Trocar a URL

Edita `server.url` em `capacitor.config.json`, commita, e o push rebuildá sozinho.
