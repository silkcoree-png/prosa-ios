import UIKit
import Capacitor
import WebKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}

// MARK: - ViewController

// Subclasse de CAPBridgeViewController (o Main.storyboard aponta pra ca).
// capacitorDidLoad() roda ANTES do webview carregar a URL, entao da pra:
//   - ajustar a sensacao nativa (zoom, bounce, gesto de voltar, barra de status)
//   - registrar o WKUserScript de limpeza de marca + viewport
//   - subir uma tela de carregamento nativa por cima do webview
@objc(ViewController)
class ViewController: CAPBridgeViewController {

    private var loadingOverlay: UIView?
    private var readyStreak = 0
    private var pollTimer: Timer?
    private var overlayShownAt = Date()

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        guard let webView = self.webView else { return }

        // app e escuro -> barra de status com texto claro (senao some no preto)
        self.setStatusBarStyle(.lightContent)

        // sensacao nativa
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = false
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0

        // cache de HTTP maior — os assets do site sao "immutable", entao valem guardar
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024,
                                   diskPath: "prosa-http-cache")

        // limpeza de marca + viewport (leve: sem varredura de DOM por mutacao)
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

          // o CSS ja esconde tudo sozinho; o observer so remove o no e e debounced
          var pending = 0;
          function schedule(){
            if(pending){ return; }
            pending = setTimeout(function(){ pending = 0; apply(); }, 1200);
          }

          apply();
          try{ document.addEventListener('DOMContentLoaded', apply); }catch(e){}
          try{
            new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true});
          }catch(e){}
        })();
        """

        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        installLoadingOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        loadingOverlay?.frame = self.view.bounds
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
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
        let delay = max(0.0, 0.45 - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIView.animate(withDuration: 0.35, animations: {
                ov.alpha = 0
            }, completion: { _ in
                ov.removeFromSuperview()
            })
        }
    }
}
