import UIKit
import WebKit

/// Hols for iPhone and iPad: the messenger https://hols-chat.ru in a full-screen WKWebView.
/// • login and chats are kept (persistent website data store);
/// • files: «📎 → Файл» opens the iOS picker (Files / Photos / camera); downloads come back with a progress bar
///   and open the share sheet — «Сохранить в Файлы», AirDrop, Telegram…;
/// • calls and voice messages: microphone and camera are granted to the site after the system prompt;
/// • links to other sites open in Safari; hols:// and hols-chat.ru links open inside;
/// • swipe from the left edge closes a window / the open chat (like «Назад»);
/// • offline screen with automatic retry; the web process is restarted if iOS kills it.
final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    static let home = URL(string: "https://hols-chat.ru/")!
    static let host = "hols-chat.ru"
    static let background = UIColor(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x16 / 255.0, alpha: 1)
    static let version = "1.0.0"

    private var web: WKWebView!
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var offline = false
    private var pendingURL: URL?
    private var downloads: [ObjectIdentifier: URL] = [:]
    private var progressObservation: NSKeyValueObservation?

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - setup
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.background

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.applicationNameForUserAgent = "HolsIOS/\(Self.version) Mobile/15E148 Safari/604.1"
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        let ucc = WKUserContentController()
        let boot = """
        window.HOLS_IOS = { platform: 'ios', version: '\(Self.version)',
          download: function (u, n) { window.webkit.messageHandlers.hols.postMessage({ type: 'download', url: u, name: n || '' }); },
          open: function (u) { window.webkit.messageHandlers.hols.postMessage({ type: 'open', url: u }); },
          haptic: function (s) { window.webkit.messageHandlers.hols.postMessage({ type: 'haptic', style: s || 'light' }); } };
        document.documentElement && document.documentElement.classList.add('ios-app');
        """
        ucc.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.add(WeakHandler(self), name: "hols")
        cfg.userContentController = ucc

        web = WKWebView(frame: view.bounds, configuration: cfg)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.isOpaque = false
        web.backgroundColor = Self.background
        web.scrollView.backgroundColor = Self.background
        web.scrollView.contentInsetAdjustmentBehavior = .never     // the site itself respects the notch (viewport-fit=cover)
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false
        web.navigationDelegate = self
        web.uiDelegate = self
        if #available(iOS 16.4, *) { web.isInspectable = true }
        view.addSubview(web)

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = UIColor(red: 0xE0 / 255.0, green: 0x31 / 255.0, blue: 0x4B / 255.0, alpha: 1)
        progress.trackTintColor = .clear
        progress.isHidden = true
        view.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.heightAnchor.constraint(equalToConstant: 3)
        ])

        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeSwipe(_:)))
        edge.edges = .left
        view.addGestureRecognizer(edge)

        web.load(URLRequest(url: pendingURL ?? Self.home))
        pendingURL = nil
    }

    /// a link from outside: hols://path or https://hols-chat.ru/path
    func open(external url: URL) {
        var target = url
        if url.scheme == "hols" {
            var path = (url.host ?? "") + url.path
            if let q = url.query { path += "?" + q }
            target = URL(string: "https://\(Self.host)/" + path) ?? Self.home
        }
        guard Self.isOwn(target) else { return }
        if web == nil { pendingURL = target } else { web.load(URLRequest(url: target)) }
    }

    static func isOwn(_ url: URL?) -> Bool {
        guard let url = url else { return true }
        let scheme = (url.scheme ?? "").lowercased()
        if ["about", "data", "blob", "javascript"].contains(scheme) { return true }
        guard let h = url.host?.lowercased() else { return true }
        return h == host || h.hasSuffix("." + host) || h.hasSuffix("onrender.com")
    }

    private func openOutside(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { self.toast("Нет приложения, чтобы открыть ссылку") }
        }
    }

    // MARK: - navigation
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = action.request.url else { decisionHandler(.allow); return }
        let scheme = (url.scheme ?? "").lowercased()
        if ["tel", "mailto", "sms", "tg", "itms-apps", "maps"].contains(scheme) { openOutside(url); decisionHandler(.cancel); return }
        if scheme == "hols" { open(external: url); decisionHandler(.cancel); return }
        if !Self.isOwn(url) { openOutside(url); decisionHandler(.cancel); return }
        if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel); return }   // target=_blank on our site
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = response.response as? HTTPURLResponse,
           let cd = http.value(forHTTPHeaderField: "Content-Disposition"), cd.lowercased().hasPrefix("attachment") {
            decisionHandler(.download); return
        }
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.scheme?.hasPrefix("http") == true { offline = false }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let code = (error as NSError).code
        if code == NSURLErrorCancelled || code == 102 /* frame load interrupted (download) */ { return }
        showOffline()
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    private func showOffline() {
        offline = true
        let html = """
        <!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover"><style>
        html,body{height:100%;margin:0;background:#141416;color:#f5f5f7;font:17px -apple-system,system-ui,sans-serif;display:grid;place-items:center}
        .c{text-align:center;padding:28px;max-width:340px}.o{width:80px;height:80px;border-radius:50%;margin:0 auto 18px;
        background:radial-gradient(circle at 32% 26%,#c9b8ff,#7b61ff 45%,#1f6bff)}h1{font-size:22px;margin:0 0 8px}
        p{color:#a1a1aa;margin:0 0 22px;line-height:1.45}button{border:0;border-radius:14px;background:#e0314b;color:#fff;font:600 17px -apple-system;padding:13px 30px}
        </style><div class=c><div class=o></div><h1>Нет соединения</h1><p>Hols не может подключиться к серверу. Проверьте интернет — мы попробуем снова через несколько секунд.</p>
        <button onclick="webkit.messageHandlers.hols.postMessage({type:'retry'})">Повторить</button></div>
        <script>setTimeout(function(){webkit.messageHandlers.hols.postMessage({type:'retry'})},8000)</script>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - camera, microphone, dialogs
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let own = origin.host == Self.host || origin.host.hasSuffix("." + Self.host) || origin.host.hasSuffix("onrender.com")
        decisionHandler(own ? .grant : .prompt)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if Self.isOwn(url) { webView.load(action.request) } else { openOutside(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }

    // MARK: - messages from the page: window.HOLS_IOS
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "download":
            if let s = body["url"] as? String, let url = URL(string: s, relativeTo: web.url)?.absoluteURL {
                download(url, name: (body["name"] as? String) ?? "")
            }
        case "open":
            if let s = body["url"] as? String, let url = URL(string: s) { openOutside(url) }
        case "haptic":
            let style: UIImpactFeedbackGenerator.FeedbackStyle = (body["style"] as? String) == "heavy" ? .heavy : (body["style"] as? String) == "medium" ? .medium : .light
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        case "retry":
            web.load(URLRequest(url: Self.home))
        default: break
        }
    }

    // MARK: - downloads → share sheet («Сохранить в Файлы», AirDrop…)
    private func download(_ url: URL, name: String) {
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var req = URLRequest(url: url)
            HTTPCookie.requestHeaderFields(with: cookies.filter { url.host?.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) ?? false })
                .forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
            self.showProgress(0.02)
            let task = URLSession.shared.downloadTask(with: req) { tmp, response, error in
                DispatchQueue.main.async {
                    self.progressObservation = nil
                    self.hideProgress()
                    guard let tmp = tmp, error == nil, ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400 else {
                        self.toast("Не удалось скачать файл"); return
                    }
                    let fileName = Self.safeName(name.isEmpty ? (response?.suggestedFilename ?? url.lastPathComponent) : name)
                    self.share(file: tmp, name: fileName)
                }
            }
            self.progressObservation = task.progress.observe(\.fractionCompleted) { p, _ in
                DispatchQueue.main.async { self.showProgress(Float(max(0.02, p.fractionCompleted))) }
            }
            task.resume()
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(Self.safeName(suggestedFilename))
        downloads[ObjectIdentifier(download)] = dest
        showProgress(0.05)
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        hideProgress()
        if let url = downloads.removeValue(forKey: ObjectIdentifier(download)) { presentShare(url) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        hideProgress()
        downloads.removeValue(forKey: ObjectIdentifier(download))
        toast("Не удалось скачать файл")
    }

    private func share(file tmp: URL, name: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        do { try FileManager.default.moveItem(at: tmp, to: dest) } catch { toast("Не удалось сохранить файл"); return }
        presentShare(dest)
    }

    private func presentShare(_ url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {           // iPad
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        }
        (presentedViewController ?? self).present(vc, animated: true)
    }

    static func safeName(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "file" : String(cleaned.prefix(180))
    }

    private func showProgress(_ v: Float) { progress.isHidden = false; progress.setProgress(v, animated: true) }
    private func hideProgress() {
        progress.setProgress(1, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.progress.isHidden = true; self.progress.progress = 0 }
    }

    // MARK: - «Назад»: swipe from the left edge
    private static let backJS = """
    (function(){try{
    var x=document.querySelectorAll('.ctx');if(x.length){x.forEach(function(e){e.remove()});return 'ok'}
    var m=document.querySelectorAll('.modal-back:not(.closing),.miniapp-back,.spk-back,.sv-back,.drawer-back');
    if(m.length){var t=m[m.length-1];var b=t.querySelector('.m-close,[data-close],[data-k=close],[data-w=close],.m-back');
    if(b){b.click();return 'ok'}if(window.S&&S.ui&&S.ui.closeAll){S.ui.closeAll();return 'ok'}t.remove();return 'ok'}
    var dr=document.querySelector('.drawer');if(dr){dr.remove();return 'ok'}
    if(window.S&&S.app&&S.app.currentChat){S.app.closeChat();return 'ok'}
    }catch(e){}return 'none'})()
    """

    @objc private func edgeSwipe(_ g: UIScreenEdgePanGestureRecognizer) {
        guard g.state == .ended, g.translation(in: view).x > 60, !offline else { return }
        web.evaluateJavaScript(Self.backJS) { result, _ in
            if (result as? String) == "ok" { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    // MARK: - small native toast
    private func toast(_ text: String) {
        let l = PaddingLabel()
        l.text = text
        l.textColor = .white
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.backgroundColor = UIColor(white: 0.12, alpha: 0.95)
        l.layer.cornerRadius = 14
        l.clipsToBounds = true
        l.numberOfLines = 0
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),
            l.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48)
        ])
        l.alpha = 0
        UIView.animate(withDuration: 0.2) { l.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 2.6, options: []) { l.alpha = 0 } completion: { _ in l.removeFromSuperview() }
    }
}

/// WKUserContentController keeps a strong reference to its handlers — this breaks the cycle.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

private final class PaddingLabel: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 16, dy: 10)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + 32, height: s.height + 20)
    }
}
