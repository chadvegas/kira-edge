import SwiftUI
import WebKit

struct WebTileWebView: NSViewRepresentable {
    let config: WebTileConfig
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.youtubeInlineFullscreenScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.forcesMobileYouTube = forcesMobileYouTube(for: config)
        context.coordinator.lastRequestedURL = targetURL(for: config)
        context.coordinator.lastReloadToken = reloadToken
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.configureReloadTimer(interval: config.reloadInterval)
        apply(config: config, to: webView)
        load(config: config, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.forcesMobileYouTube = forcesMobileYouTube(for: config)
        context.coordinator.webView = webView
        context.coordinator.configureReloadTimer(interval: config.reloadInterval)
        apply(config: config, to: webView)

        guard let target = targetURL(for: config) else { return }
        if context.coordinator.lastRequestedURL?.absoluteString != target.absoluteString {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.lastRequestedURL = target
            load(config: config, in: webView)
            return
        }

        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDownReloadTimer()
    }

    private func apply(config: WebTileConfig, to webView: WKWebView) {
        webView.pageZoom = config.zoom
        let target = targetURL(for: config)
        if usesMobileYouTubeSurface(target) {
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        } else if config.usesDesktopUserAgent && !usesGoogleAuthenticationSurface(target) {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        } else {
            webView.customUserAgent = nil
        }
    }

    private func load(config: WebTileConfig, in webView: WKWebView) {
        guard let url = targetURL(for: config) else { return }
        webView.load(URLRequest(url: url))
    }

    private func usesGoogleAuthenticationSurface(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }

        return host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
            || host == "google.com"
            || host.hasSuffix(".google.com")
            || host == "accounts.google.com"
    }

    private func usesMobileYouTubeSurface(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "m.youtube.com"
    }

    private func targetURL(for config: WebTileConfig) -> URL? {
        guard let url = config.url else { return nil }
        guard forcesMobileYouTube(for: config), let mobileURL = mobileYouTubeURL(from: url) else {
            return url
        }
        return mobileURL
    }

    private func forcesMobileYouTube(for config: WebTileConfig) -> Bool {
        guard let url = config.url, let host = url.host()?.lowercased() else { return false }
        let path = url.path.lowercased()

        guard host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" || host == "youtu.be" else {
            return false
        }

        if path.hasPrefix("/tv") || path.hasPrefix("/live_chat") || path.hasPrefix("/embed") {
            return false
        }

        return host == "m.youtube.com"
    }

    private func mobileYouTubeURL(from url: URL) -> URL? {
        guard let host = url.host()?.lowercased() else { return nil }

        if host == "youtu.be" {
            let videoID = url.pathComponents.dropFirst().first
            var components = URLComponents()
            components.scheme = "https"
            components.host = "m.youtube.com"
            components.path = "/watch"
            if let videoID {
                components.queryItems = [URLQueryItem(name: "v", value: videoID)]
            }
            return components.url
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = "m.youtube.com"
        return components?.url
    }

    private static let youtubeInlineFullscreenScript = """
    (() => {
      const host = window.location.hostname.toLowerCase();
      if (!host.endsWith('youtube.com') && host !== 'youtu.be') return;
      if (window.__xeneonInlineFullscreenInstalled) return;
      window.__xeneonInlineFullscreenInstalled = true;

      const expandedClass = 'xeneon-player-expanded';
      const style = document.createElement('style');
      style.textContent = `
        html.${expandedClass},
        html.${expandedClass} body {
          background: #000 !important;
          height: 100% !important;
          margin: 0 !important;
          overflow: hidden !important;
          width: 100% !important;
        }

        html.${expandedClass} ytm-mobile-topbar-renderer,
        html.${expandedClass} ytm-searchbox,
        html.${expandedClass} ytm-pivot-bar-renderer,
        html.${expandedClass} ytm-tabs-renderer,
        html.${expandedClass} ytm-bottom-sheet-renderer,
        html.${expandedClass} ytm-menu-popup-renderer,
        html.${expandedClass} #masthead,
        html.${expandedClass} #guide,
        html.${expandedClass} #guide-content,
        html.${expandedClass} tp-yt-app-drawer,
        html.${expandedClass} ytd-mini-guide-renderer,
        html.${expandedClass} #secondary,
        html.${expandedClass} #below,
        html.${expandedClass} #related,
        html.${expandedClass} ytd-comments,
        html.${expandedClass} ytd-watch-metadata,
        html.${expandedClass} ytd-watch-next-secondary-results-renderer,
        html.${expandedClass} ytd-rich-grid-renderer,
        html.${expandedClass} ytd-compact-video-renderer,
        html.${expandedClass} ytd-rich-item-renderer,
        html.${expandedClass} ytm-watch-next-renderer,
        html.${expandedClass} ytm-single-column-watch-next-results-renderer,
        html.${expandedClass} ytm-section-list-renderer,
        html.${expandedClass} ytm-item-section-renderer,
        html.${expandedClass} ytm-engagement-panel,
        html.${expandedClass} ytm-watch-metadata,
        html.${expandedClass} ytm-slim-video-metadata-renderer,
        html.${expandedClass} ytm-compact-video-renderer,
        html.${expandedClass} ytm-video-with-context-renderer,
        html.${expandedClass} ytm-rich-item-renderer,
        html.${expandedClass} ytm-rich-grid-renderer,
        html.${expandedClass} ytm-reel-shelf-renderer,
        html.${expandedClass} .ytp-endscreen-content,
        html.${expandedClass} .ytp-endscreen-paginate,
        html.${expandedClass} .ytp-autonav-endscreen-upnext-container,
        html.${expandedClass} .ytp-ce-element,
        html.${expandedClass} .ytp-cards-teaser,
        html.${expandedClass} .ytp-cards-button,
        html.${expandedClass} .ytp-pause-overlay,
        html.${expandedClass} .ytp-suggestion-set,
        html.${expandedClass} .ytp-suggestion-link,
        html.${expandedClass} .ytp-videowall-still {
          display: none !important;
          visibility: hidden !important;
          pointer-events: none !important;
        }

        html.${expandedClass} ytd-app,
        html.${expandedClass} ytm-app,
        html.${expandedClass} ytd-page-manager,
        html.${expandedClass} ytm-browse,
        html.${expandedClass} ytd-watch-flexy,
        html.${expandedClass} ytm-watch {
          display: block !important;
          background: #000 !important;
          height: 100vh !important;
          max-height: 100vh !important;
          margin: 0 !important;
          overflow: hidden !important;
          padding: 0 !important;
          width: 100vw !important;
        }

        html.${expandedClass} #page-manager,
        html.${expandedClass} #columns,
        html.${expandedClass} #primary,
        html.${expandedClass} #primary-inner {
          background: #000 !important;
          height: 100vh !important;
          width: 100% !important;
          max-width: none !important;
          margin: 0 !important;
          padding: 0 !important;
          overflow: hidden !important;
        }

        html.${expandedClass} ytm-player,
        html.${expandedClass} ytd-player,
        html.${expandedClass} #player,
        html.${expandedClass} #player-api,
        html.${expandedClass} #player-container-outer,
        html.${expandedClass} #player-container,
        html.${expandedClass} #player-container-id,
        html.${expandedClass} .player-container,
        html.${expandedClass} .player-api,
        html.${expandedClass} #movie_player,
        html.${expandedClass} .html5-video-player {
          background: #000 !important;
          bottom: auto !important;
          height: 100vh !important;
          inset: 0 !important;
          left: 0 !important;
          margin: 0 !important;
          max-width: none !important;
          max-height: none !important;
          min-height: 100vh !important;
          overflow: hidden !important;
          padding: 0 !important;
          position: fixed !important;
          right: auto !important;
          top: 0 !important;
          transform: none !important;
          width: 100vw !important;
          z-index: 2147483647 !important;
        }

        html.${expandedClass} .html5-video-container,
        html.${expandedClass} .html5-main-video,
        html.${expandedClass} video {
          background: #000 !important;
          height: 100% !important;
          inset: 0 !important;
          left: 0 !important;
          max-height: none !important;
          max-width: none !important;
          object-fit: contain !important;
          position: absolute !important;
          top: 0 !important;
          transform: none !important;
          width: 100% !important;
        }

        html.${expandedClass} .ytp-chrome-bottom {
          bottom: 0 !important;
          left: 12px !important;
          max-width: calc(100vw - 24px) !important;
          width: calc(100vw - 24px) !important;
        }

        html.${expandedClass} .ytp-gradient-bottom {
          bottom: 0 !important;
          width: 100vw !important;
        }
      `;
      document.documentElement.appendChild(style);
      let lastFullscreenIntentAt = 0;
      let scrollTopBeforeExpand = 0;

      const fullscreenButtonFor = (event) => {
        const path = eventPathFor(event);
        return path.find((node) => {
          if (!node || node.nodeType !== 1) return false;
          if (node.classList?.contains('ytp-fullscreen-button')) return true;

          const tagName = node.tagName?.toLowerCase() || '';
          const role = node.getAttribute?.('role') || '';
          const isButtonLike = tagName === 'button' || role.toLowerCase() === 'button';
          if (!isButtonLike) return false;

          const label = `${node.getAttribute?.('aria-label') || ''} ${node.getAttribute?.('title') || ''}`.toLowerCase();
          return label.includes('full screen') || label.includes('fullscreen');
        }) || null;
      };

      const eventPathFor = (event) => {
        const target = event.target;
        if (event.composedPath) return event.composedPath();
        if (!target) return [];

        const path = [];
        let node = target;
        while (node) {
          path.push(node);
          node = node.parentElement || node.parentNode;
        }
        return path;
      };

      const setExpandedClass = () => {
        if (!isExpanded()) {
          scrollTopBeforeExpand = document.scrollingElement?.scrollTop || window.scrollY || 0;
        }

        document.documentElement.classList.add(expandedClass);
        document.body?.classList.add(expandedClass);
      };

      const removeExpandedClass = () => {
        document.documentElement.classList.remove(expandedClass);
        document.body?.classList.remove(expandedClass);
      };

      const isExpanded = () => document.documentElement.classList.contains(expandedClass);

      const clearYouTubeExpandedState = () => {
        const watchFlexy = document.querySelector('ytd-watch-flexy');
        if (watchFlexy) {
          [
            'fullscreen',
            'fullscreen_',
            'fullscreen-requested_',
            'theater',
            'theater-requested_',
            'is-watch-page-embed'
          ].forEach((attribute) => watchFlexy.removeAttribute(attribute));
        }

        document.querySelector('ytm-watch')?.removeAttribute('fullscreen');
        document.querySelector('ytm-player')?.removeAttribute('fullscreen');
        document.querySelector('#movie_player')?.classList.remove('ytp-fullscreen', 'ytp-big-mode');
        document.querySelectorAll('.ytp-fullscreen').forEach((node) => node.classList.remove('ytp-fullscreen'));
        document.body?.classList.remove('fullscreen-scroll-lock');

        if (document.fullscreenElement && document.exitFullscreen) {
          document.exitFullscreen().catch(() => {});
        }
      };

      const dispatchPlayerResize = () => {
        window.dispatchEvent(new Event('resize'));
        window.setTimeout(() => window.dispatchEvent(new Event('resize')), 100);
        window.setTimeout(() => window.dispatchEvent(new Event('resize')), 300);
      };

      const expandPlayerInPage = () => {
        setExpandedClass();
        dispatchPlayerResize();
      };

      const collapsePlayerInPage = () => {
        removeExpandedClass();
        clearYouTubeExpandedState();
        dispatchPlayerResize();

        window.setTimeout(() => {
          if (document.scrollingElement) {
            document.scrollingElement.scrollTop = scrollTopBeforeExpand;
          } else {
            window.scrollTo(0, scrollTopBeforeExpand);
          }
        }, 0);
      };

      const togglePlayerInPage = () => {
        if (isExpanded()) {
          collapsePlayerInPage();
          return;
        }

        expandPlayerInPage();
      };

      const interceptFullscreenButton = (event) => {
        if (!fullscreenButtonFor(event)) return;

        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();

        const now = performance.now();
        if (now - lastFullscreenIntentAt < 450) return;
        lastFullscreenIntentAt = now;
        togglePlayerInPage();
      };

      ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'touchstart', 'touchend', 'click'].forEach((eventName) => {
        document.addEventListener(eventName, interceptFullscreenButton, { capture: true, passive: false });
      });

      document.addEventListener('keydown', (event) => {
        const tagName = event.target?.tagName?.toLowerCase();
        if (tagName === 'input' || tagName === 'textarea' || event.target?.isContentEditable) return;

        if (event.key?.toLowerCase() === 'f') {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();
          togglePlayerInPage();
        } else if (event.key === 'Escape' && isExpanded()) {
          event.preventDefault();
          event.stopPropagation();
          event.stopImmediatePropagation();
          collapsePlayerInPage();
        }
      }, true);
    })();
    """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var lastReloadToken = 0
        var lastRequestedURL: URL?
        var forcesMobileYouTube = false

        weak var webView: WKWebView?
        private var reloadTimer: Timer?
        private var reloadInterval: TimeInterval = 0

        func configureReloadTimer(interval: TimeInterval) {
            // Only rebuild the timer when the requested interval actually changes,
            // so steady-state updateNSView calls don't reset the countdown.
            guard interval != reloadInterval else { return }
            reloadInterval = interval
            reloadTimer?.invalidate()
            reloadTimer = nil

            guard interval > 0 else { return }

            reloadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = self?.webView?.reload()
                }
            }
        }

        func tearDownReloadTimer() {
            reloadTimer?.invalidate()
            reloadTimer = nil
            reloadInterval = 0
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if
                forcesMobileYouTube,
                let url = navigationAction.request.url,
                let mobileURL = Self.mobileYouTubeURL(from: url),
                mobileURL.absoluteString != url.absoluteString
            {
                webView.load(URLRequest(url: mobileURL))
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else {
                return nil
            }

            if
                forcesMobileYouTube,
                let url = navigationAction.request.url,
                let mobileURL = Self.mobileYouTubeURL(from: url)
            {
                webView.load(URLRequest(url: mobileURL))
            } else {
                webView.load(navigationAction.request)
            }

            return nil
        }

        private static func mobileYouTubeURL(from url: URL) -> URL? {
            guard let host = url.host()?.lowercased() else { return nil }
            guard host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" || host == "youtu.be" else {
                return nil
            }

            if host == "youtu.be" {
                let videoID = url.pathComponents.dropFirst().first
                var components = URLComponents()
                components.scheme = "https"
                components.host = "m.youtube.com"
                components.path = "/watch"
                if let videoID {
                    components.queryItems = [URLQueryItem(name: "v", value: videoID)]
                }
                return components.url
            }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            components?.host = "m.youtube.com"
            return components?.url
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let css = """
            if (!document.getElementById('xeneon-readable-style')) {
              const style = document.createElement('style');
              style.id = 'xeneon-readable-style';
              style.innerHTML = `
                html, body { overscroll-behavior: contain; }
                video { max-width: 100% !important; }
              `;
              document.head.appendChild(style);
            }
            """
            webView.evaluateJavaScript(css, completionHandler: nil)
        }
    }
}

final class FocusableWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
    }
}
