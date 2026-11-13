# Prosa Silk — app iOS

Empacota o site publicado como app iOS instalável. O app abre a URL definida em
`capacitor.config.json` (`server.url`) dentro de um WebView nativo.

- nome exibido: **Prosa Silk**
- bundle id: `com.prosasilk.app`
- URL carregada: `https://alma-conversation-garden.lovable.app/chat`
- scheme próprio: **`prosasilk://`**
- wrapper: Capacitor 7 (iOS) · mínimo iOS 14.0

> **Por que não empacota local?** O `/api/chat` só aceita requisições da **mesma origem**
> (`isSameOrigin`). Servido de `capacitor://localhost` o chat devolveria 403. Então o WebView
> é obrigado a carregar a URL remota — a velocidade de abertura é limitada pela rede.
> É por isso que a captura de foto é **nativa**: ela não depende do site ter carregado.

## Como sai o IPA

Build no GitHub Actions (`macos-latest`) — não dá pra compilar IPA no Windows:

1. `npm install`
2. `npx cap add ios` + `npx cap sync ios`
3. aplica os patches nativos (tabela abaixo)
4. `xcodebuild` gera um `.app` **sem assinatura**
5. empacota em `Payload/` → `app.ipa`
6. sobe o `app.ipa` como artifact do workflow

Dispara a cada push em `main`, ou manual em **Actions → build-ipa → Run workflow**.

## Patches nativos (aplicados no CI depois do `cap sync`)

| arquivo no repo | destino | o que faz |
|---|---|---|
| `ios-assets/AppIcon-512@2x.png` | `AppIcon.appiconset/` | ícone do app |
| `ios-assets/splash-2732x2732*.png` | `Splash.imageset/` | tela de abertura |
| `ios-patches/LaunchScreen.storyboard` | `Base.lproj/` | fundo preto na splash |
| `ios-patches/Main.storyboard` | `Base.lproj/` | aponta a cena pro `ViewController` local |
| `ios-patches/AppDelegate.swift` | `App/App/` | cena nativa inteira (abaixo) |
| `www/logo.png` | `public/logo.png` | logo do overlay |
| *(PlistBuddy)* | `Info.plist` | scheme `prosasilk://` + `NSCameraUsageDescription` |

## O que o `ViewController` faz

Declarado dentro do próprio `AppDelegate.swift` (pra não mexer no `.xcodeproj`).

**Sempre:**
- barra de status clara (o app é escuro) e sem zoom/bounce/indicadores;
- URL cache 64 MB / 512 MB;
- **overlay de carregamento nativo** (logo + spinner sobre preto, timeout 20 s);
- corte da marca do hospedeiro (CSS em `.atDocumentStart` + observer debounced 1,2 s);
- **cortina preta** quando o app vai pro segundo plano — a conversa não aparece no app switcher.

**Deep link `prosasilk://foto`** (ou `prosasilk://galeria`):
- sobe **câmera nativa** (`UIImagePickerController`) ou **galeria** (`PHPickerViewController`) **na hora**,
  sem esperar o site carregar;
- a foto é redimensionada (máx 1400 px, JPEG 0.72) e injetada no campo escondido do site
  (`input[type=file].files` + evento `change`), que dispara o `onPickFiles` do próprio site;
- quando a miniatura aparece no compositor, o app chama `form.requestSubmit()` —
  ou seja, **foto → resposta da IA sem tocar na tela**.

**Gatilho pelos botões de volume** (com o app aberto):
- observa `AVAudioSession.outputVolume`;
- se detecta **volume+ e volume− em sequência rápida (< 0,5 s)**, entende como as duas teclas
  e abre a câmera;
- devolve o volume ao valor anterior.

## Gatilhos no iPhone — e a verdade sobre os botões de volume

**O iOS não tem como abrir um app apertando os dois botões de volume.** Isso não existe:
os botões de volume não são mapeáveis pelo sistema. O que existe, e fica em
**Ajustes → Acessibilidade**, é o **Tocar no verso (Back Tap)**.

Como configurar o caminho mais rápido e discreto:

1. **Atalhos** (app nativo) → **+** → nova automação/atalho, nome "Prosa Foto".
2. Ação: **Abrir URL** → `prosasilk://foto`
3. **Ajustes → Acessibilidade → Toque → Tocar no verso → Toque duplo** → escolhe "Prosa Foto".

A partir daí: **duas batidinhas no verso do celular** → o app abre **já com a câmera na tela**.
Se preferir a galeria, use `prosasilk://galeria` no atalho.

Com o app já aberto, o gesto dos botões de volume também dispara a câmera (ver acima).

> O gatilho de volume mostra o HUD de volume por um instante — é do sistema, não dá pra esconder.
> O Back Tap é o que passa despercebido.

## Instalar no iPhone

1. **Actions** → último run verde → baixa o artifact **app-ipa**.
2. Extrai → fica o `app.ipa`.
3. **Sideloadly** no PC, iPhone plugado, arrasta o `app.ipa`, põe teu Apple ID.
4. Start → confia no perfil em Ajustes → Geral → VPN e Dispositivo.

> App ID grátis expira em 7 dias. O app carrega o site, então **precisa de internet**.

## Trocar a URL

Edita `server.url` em `capacitor.config.json`, commita, e o push rebuildá sozinho.
