# Estudo — app iOS (wrapper do site)

Empacota o site publicado como um app iOS instalável. O app abre a URL definida em
`capacitor.config.json` (`server.url`) dentro de um WebView nativo.

- URL carregada: https://alma-conversation-garden.lovable.app
- Bundle id: `com.estudo.app`
- Wrapper: Capacitor 7 (iOS)

## Como sai o IPA

Não dá pra compilar IPA no Windows — precisa de macOS/Xcode. Por isso o build roda no
GitHub Actions (runner `macos-latest`):

1. `npm install`
2. `npx cap add ios` + `npx cap sync ios`
3. `xcodebuild` gera um `.app` **sem assinatura**
4. o `.app` é empacotado em `Payload/` e vira `app.ipa`
5. o `app.ipa` sobe como **artifact** do workflow

O build dispara sozinho a cada push em `main` (ou manual em **Actions → build-ipa → Run workflow**).

## Instalar no iPhone

1. Aba **Actions** → último run verde → baixa o artifact **app-ipa**.
2. Extrai o zip → fica o `app.ipa`.
3. Abre o **Sideloadly** no PC, conecta o iPhone, arrasta o `app.ipa`, põe teu Apple ID.
4. Start. O Sideloadly assina na hora com teu Apple ID.

> App ID grátis expira em 7 dias — reassina quando pedir.
