//
//  AppDelegate.swift
//  Prosa Silk
//
//  Cena nativa do wrapper Capacitor:
//   - barra de status clara, sem zoom/bounce, cache maior
//   - overlay de carregamento nativo (logo + spinner)
//   - corte da marca do hospedeiro no WebView
//   - deep link prosasilk://foto | prosasilk://galeria -> camera/galeria NATIVA na hora
//   - gatilho pelos botoes de volume (heuristica: + e - em sequencia rapida)
//   - cortina preta no app switcher (nao vaza a conversa)
//
//  O site exige mesma origem no /api/chat (isSameOrigin), entao o WebView e
//  OBRIGADO a carregar a URL remota. A camera nativa existe justamente pra
//  nao depender do site ter carregado.
//

import UIKit
import Capacitor
import WebKit
import AVFoundation
import MediaPlayer
import PhotosUI

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var curtain: UIView?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // app aberto por deep link (cold start): guarda pra ViewController consumir
        if let url = launchOptions?[.url] as? URL {
            ViewController.pendingDeepLink = url
        }
        return true
    }

    // MARK: - Cortina de privacidade (app switcher)

    func applicationWillResignActive(_ application: UIApplication) {
        guard let window = self.window, curtain == nil else { return }
        let cover = UIView(frame: window.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .black
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blur.frame = cover.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.addSubview(blur)
        window.addSubview(cover)
        curtain = cover
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard let cover = curtain else { return }
        curtain = nil
        UIView.animate(withDuration: 0.15, animations: { cover.alpha = 0 }) { _ in
            cover.removeFromSuperview()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}

    // MARK: - Deep link

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.scheme?.lowercased() == "prosasilk" {
            if let root = window?.rootViewController as? ViewController,
               root.isViewLoaded, root.view.window != nil,
               root.handleDeepLink(url) {
                return true
            }
            // ainda nao deu pra apresentar: deixa pro primeiro viewDidAppear
            ViewController.pendingDeepLink = url
            return true
        }
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}

// MARK: - ViewController

@objc(ViewController)
class ViewController: CAPBridgeViewController {

    /// Deep link recebido antes de a tela existir (cold start).
    static var pendingDeepLink: URL?

    private var loadingOverlay: UIView?
    private var readyStreak = 0
    private var pollTimer: Timer?
    private var overlayShownAt = Date()

    // volume
    private var volumeObservation: NSKeyValueObservation?
    private var lastVolume: Float = 0
    private var baselineVolume: Float = 0.5
    private var lastDirection = 0
    private var lastChangeAt = Date.distantPast
    private var volumeView: MPVolumeView?
    private var lastTriggerAt = Date.distantPast

    // MARK: - Ciclo de vida

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        guard let webView = self.webView else { return }

        self.setStatusBarStyle(.lightContent)

        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = false
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0

        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024,
                                   diskPath: "prosa-http-cache")

        injectScript(webView)
        installLoadingOverlay()
        startVolumeWatch()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let url = ViewController.pendingDeepLink {
            ViewController.pendingDeepLink = nil
            _ = handleDeepLink(url)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        loadingOverlay?.frame = self.view.bounds
    }

    // MARK: - Script injetado

    private func injectScript(_ webView: WKWebView) {
        let js = """
        (function(){
          try{
            var vp = document.querySelector('meta[name="viewport"]');
            if(!vp){
              vp = document.createElement('meta');
              vp.setAttribute('name','viewport');
              (document.head||document.documentElement).appendChild(vp);
            }
            vp.setAttribute('content','width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no');
          }catch(e){}

          var CSS = "#lovable-badge,#lovable-badge *,#lovable-badge-cta,[id^='lovable-badge']{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;width:0!important;height:0!important;min-width:0!important;min-height:0!important;max-width:0!important;max-height:0!important;overflow:hidden!important;position:absolute!important;left:-9999px!important;top:-9999px!important;z-index:-2147483647!important}";

          function apply(){
            try{
              if(!document.getElementById('__prosa_kill')){
                var s = document.createElement('style');
                s.id = '__prosa_kill';
                s.type = 'text/css';
                s.appendChild(document.createTextNode(CSS));
                (document.head||document.documentElement).appendChild(s);
              }
            }catch(e){}
            try{
              var n = document.getElementById('lovable-badge');
              if(n && n.parentNode){ n.parentNode.removeChild(n); }
            }catch(e){}
          }

          var pending = 0;
          function schedule(){
            if(pending){ return; }
            pending = setTimeout(function(){ pending = 0; apply(); }, 1200);
          }

          apply();
          try{ document.addEventListener('DOMContentLoaded', apply); }catch(e){}
          try{ new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true}); }catch(e){}
        })();
        """
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
    }

    // MARK: - Deep link -> captura nativa

    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "prosasilk" else { return false }
        let target = ((url.host ?? "") + url.path).lowercased()
        guard target.contains("foto") || target.contains("galeria") || target.contains("camera") else { return false }
        let wantsLibrary = target.contains("galeria")
        DispatchQueue.main.async { [weak self] in
            self?.presentCapture(library: wantsLibrary)
        }
        return true
    }

    private func presentCapture(library: Bool) {
        guard presentedViewController == nil else { return }
        if library || !UIImagePickerController.isSourceTypeAvailable(.camera) {
            var cfg = PHPickerConfiguration()
            cfg.filter = .images
            cfg.selectionLimit = 1
            let picker = PHPickerViewController(configuration: cfg)
            picker.delegate = self
            present(picker, animated: false)
        } else {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = self
            present(picker, animated: false)
        }
    }

    // MARK: - Entrega da foto pro WebView

    private func deliver(_ image: UIImage) {
        guard let data = jpegData(from: image) else { return }
        injectPhoto(data.base64EncodedString(), tries: 0)
        if data.count > 0 { scheduleAutoSend(tries: 0) }
    }

    private func jpegData(from image: UIImage, maxDimension: CGFloat = 1400, quality: CGFloat = 0.72) -> Data? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, maxDimension / max(w, h))
        if scale < 1 {
            let size = CGSize(width: floor(w * scale), height: floor(h * scale))
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            return resized.jpegData(compressionQuality: quality)
        }
        return image.jpegData(compressionQuality: quality)
    }

    private func injectPhoto(_ b64: String, tries: Int) {
        guard let webView = self.webView else { return }
        let js = """
        (function(b64){
          try{
            var inputs = document.querySelectorAll('input[type=file]');
            if(!inputs.length) return 0;
            var pick = null;
            for (var i=0;i<inputs.length;i++){
              var a = inputs[i].getAttribute('accept')||'';
              if(a.indexOf('image')>=0){ pick = inputs[i]; if(inputs[i].hasAttribute('capture')) break; }
            }
            if(!pick) pick = inputs[0];
            var bin = atob(b64), len = bin.length, arr = new Uint8Array(len);
            for (var j=0;j<len;j++) arr[j] = bin.charCodeAt(j);
            var file = new File([arr], 'foto.jpg', {type:'image/jpeg'});
            var dt = new DataTransfer();
            dt.items.add(file);
            pick.files = dt.files;
            pick.dispatchEvent(new Event('change', {bubbles:true}));
            return 1;
          }catch(e){ return -1; }
        })("\(b64)")
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            if (result as? NSNumber)?.intValue == 1 { return }
            guard tries < 50 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.injectPhoto(b64, tries: tries + 1) }
        }
    }

    private func scheduleAutoSend(tries: Int) {
        guard let webView = self.webView else { return }
        let js = """
        (function(){
          try{
            var form = document.querySelector('form');
            if(!form) return 0;
            var btn = form.querySelector('button[type=submit]');
            if(!btn || btn.disabled) return 0;
            if(!document.querySelector('img[alt="Foto pra enviar"]')) return 0;
            form.requestSubmit();
            return 1;
          }catch(e){ return -1; }
        })()
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self = self else { return }
                if (result as? NSNumber)?.intValue == 1 { return }
                guard tries < 16 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.scheduleAutoSend(tries: tries + 1) }
            }
        }
    }

    // MARK: - Gatilho pelos botoes de volume

    private func startVolumeWatch() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        baselineVolume = session.outputVolume
        lastVolume = baselineVolume
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self = self, let v = change.newValue else { return }
            self.volumeChanged(v)
        }
    }

    private func volumeChanged(_ v: Float) {
        let dir = v > lastVolume + 0.001 ? 1 : (v < lastVolume - 0.001 ? -1 : 0)
        lastVolume = v
        guard dir != 0 else { return }

        let now = Date()
        if dir != lastDirection, now.timeIntervalSince(lastChangeAt) < 0.5 {
            lastDirection = 0
            lastChangeAt = .distantPast
            guard now.timeIntervalSince(lastTriggerAt) > 1.5 else { return }
            lastTriggerAt = now
            restoreVolume()
            DispatchQueue.main.async { [weak self] in self?.presentCapture(library: false) }
        } else {
            lastDirection = dir
            lastChangeAt = now
        }
    }

    private func restoreVolume() {
        if volumeView == nil {
            let vv = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 40, height: 40))
            self.view.addSubview(vv)
            volumeView = vv
        }
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        let target = baselineVolume
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            slider.value = target
            slider.sendActions(for: .touchUpInside)
        }
    }

    // MARK: - Tela de carregamento nativa

    private func installLoadingOverlay() {
        let ov = UIView(frame: self.view.bounds)
        ov.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ov.backgroundColor = .black

        let logoView = UIImageView(image: ViewController.bundleLogo())
        logoView.contentMode = .scaleAspectFit
        logoView.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = UIColor(white: 1.0, alpha: 0.7)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        ov.addSubview(logoView)
        ov.addSubview(spinner)
        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: ov.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: ov.centerYAnchor, constant: -40),
            logoView.widthAnchor.constraint(equalToConstant: 132),
            logoView.heightAnchor.constraint(equalToConstant: 132),
            spinner.centerXAnchor.constraint(equalTo: ov.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 28)
        ])

        self.view.addSubview(ov)
        self.loadingOverlay = ov
        self.overlayShownAt = Date()
        self.readyStreak = 0
        startPolling()
    }

    private static func bundleLogo() -> UIImage? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "public"),
            Bundle.main.url(forResource: "logo", withExtension: "png")
        ]
        for case let url? in candidates {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                return img
            }
        }
        return nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if Date().timeIntervalSince(self.overlayShownAt) > 20 {
                timer.invalidate()
                self.hideLoadingOverlay()
                return
            }
            self.probeReady()
        }
    }

    private func probeReady() {
        guard let webView = self.webView else { return }
        let js = "(function(){try{var b=document.body;if(!b)return 0;if(document.readyState!=='complete')return 0;var t=(b.innerText||'').trim();return t.length>40?1:0;}catch(e){return 0;}})()"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            if let n = result as? NSNumber, n.intValue == 1 {
                self.readyStreak += 1
            } else {
                self.readyStreak = 0
            }
            if self.readyStreak >= 2 {
                self.pollTimer?.invalidate()
                self.hideLoadingOverlay()
            }
        }
    }

    private func hideLoadingOverlay() {
        guard let ov = self.loadingOverlay else { return }
        self.loadingOverlay = nil
        let elapsed = Date().timeIntervalSince(self.overlayShownAt)
        let delay = max(0.0, 0.35 - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIView.animate(withDuration: 0.3, animations: {
                ov.alpha = 0
            }, completion: { _ in
                ov.removeFromSuperview()
            })
        }
    }
}

// MARK: - Pickers

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: false) { [weak self] in
            if let image = image { self?.deliver(image) }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: false, completion: nil)
    }
}

extension ViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            picker.dismiss(animated: false, completion: nil)
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                picker.dismiss(animated: false) {
                    if let image = image { self?.deliver(image) }
                }
            }
        }
    }
}
