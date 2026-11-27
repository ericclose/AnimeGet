import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/anime_models.dart';
import 'http_client.dart';

class _CachedUrl {
  const _CachedUrl(this.url, this.timestamp);
  final String url;
  final DateTime timestamp;
}

/// Video URL resolver combining fast HTTP/AES extraction with HeadlessInAppWebView JS Hook fallback.
class VideoUrlResolver {
  VideoUrlResolver(this._dio);

  final Dio _dio;
  final Map<String, _CachedUrl> _resolvedCache = <String, _CachedUrl>{};

  static final encrypt.Key _v2PlayerKey =
      encrypt.Key.fromUtf8('ABABEF777999CCCD');

  static final RegExp _playDataRegex = RegExp(
    r'''playData\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*\)''',
  );

  static final RegExp _mediaUrlRegex = RegExp(
    r'''https?://[^\s"'<>\\]+\.(?:m3u8|mp4|flv|mkv|webm|m4v)(?:\?[^\s"'<>\\]*)?''',
    caseSensitive: false,
  );

  static final RegExp _hlsLoadSourceRegex = RegExp(
    r'''loadSource\s*\(\s*['"](https?://[^'"]+)['"]\s*\)''',
    caseSensitive: false,
  );

  static final RegExp _artplayerUrlRegex = RegExp(
    r'''url\s*:\s*['"](https?://[^'"]+)['"]''',
    caseSensitive: false,
  );

  static const String _hookScriptSource = r'''
(function() {
  window.capturedVideoUrl = null;

  function isCandidateVideoUrl(url) {
    if (!url || typeof url !== 'string') return false;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
    const cleanUrl = url.split('?')[0].toLowerCase();
    if (/\.(jpg|jpeg|png|gif|webp|svg|ico|bmp|css|js|woff|woff2|ttf|eot)$/i.test(cleanUrl)) {
      return false;
    }
    if (cleanUrl.includes('douyin.com/note') || cleanUrl.includes('bilibili.com/read') || cleanUrl.includes('weibo.com')) {
      return false;
    }
    if (cleanUrl.includes('/danmuku') || cleanUrl.includes('/danmaku') || cleanUrl.includes('google-analytics') || cleanUrl.includes('googletagmanager')) {
      return false;
    }
    return true;
  }

  function notifyNative(url, source) {
    if (!isCandidateVideoUrl(url)) return;
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('videoCaptured', JSON.stringify({ url: url, source: source }));
    } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.videoCaptured) {
      window.webkit.messageHandlers.videoCaptured.postMessage(JSON.stringify({ url: url, source: source }));
    }
  }

  const originalSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
  if (originalSrcDescriptor) {
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      get() { return originalSrcDescriptor.get.call(this); },
      set(val) {
        if (isCandidateVideoUrl(val)) {
          notifyNative(val, 'HTMLMediaElement.src[' + (this.tagName || '') + ']');
        }
        originalSrcDescriptor.set.call(this, val);
      },
      configurable: true
    });
  }

  const originalSetAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value) {
    if (name === 'src' && value) {
      const tag = (this.tagName || '').toLowerCase();
      if ((tag === 'video' || tag === 'source') && isCandidateVideoUrl(value)) {
        notifyNative(value, 'setAttribute[' + tag + ']');
      }
    }
    return originalSetAttribute.apply(this, arguments);
  };

  function wrapHls(val) {
    if (!val || !val.prototype || val.prototype._hooked) return val;
    val.prototype._hooked = true;
    const originalLoadSource = val.prototype.loadSource;
    val.prototype.loadSource = function(src) {
      if (src && isCandidateVideoUrl(src)) {
        notifyNative(src, 'Hls.loadSource');
      }
      return originalLoadSource.apply(this, arguments);
    };
    return val;
  }

  if (window.Hls) {
    wrapHls(window.Hls);
  }
  let currentHls = window.Hls;
  Object.defineProperty(window, 'Hls', {
    get() { return currentHls; },
    set(val) {
      currentHls = wrapHls(val);
    },
    configurable: true
  });

  function wrapArtplayer(fn) {
    if (!fn || fn._hooked) return fn;
    const wrapper = function(options) {
      if (options && options.url && typeof options.url === 'string') {
        if (isCandidateVideoUrl(options.url)) {
          notifyNative(options.url, 'Artplayer.options.url');
        }
      }
      return new fn(options);
    };
    wrapper.prototype = fn.prototype;
    wrapper._hooked = true;
    try {
      for (const key of Object.getOwnPropertyNames(fn)) {
        wrapper[key] = fn[key];
      }
    } catch(e) {}
    return wrapper;
  }

  if (window.Artplayer) {
    window.Artplayer = wrapArtplayer(window.Artplayer);
  }
  let currentArtplayer = window.Artplayer;
  Object.defineProperty(window, 'Artplayer', {
    get() { return currentArtplayer; },
    set(val) {
      currentArtplayer = wrapArtplayer(val);
    },
    configurable: true
  });

  setInterval(function() {
    if (window.capturedVideoUrl) return;
    if (window.art && window.art.url && typeof window.art.url === 'string') {
      if (isCandidateVideoUrl(window.art.url)) {
        notifyNative(window.art.url, 'window.art.url');
      }
    }
  }, 200);
})();
''';

  String? decryptV2Player(String cipherBase64, String ivHex) {
    try {
      final ivBytes = <int>[];
      for (var i = 0; i + 1 < ivHex.length; i += 2) {
        final byte = int.tryParse(ivHex.substring(i, i + 2), radix: 16);
        if (byte != null) {
          ivBytes.add(byte);
        }
      }
      if (ivBytes.length != 16) return null;

      final iv = encrypt.IV(Uint8List.fromList(ivBytes));
      final encrypter = encrypt.Encrypter(
        encrypt.AES(_v2PlayerKey, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );
      return encrypter.decrypt64(cipherBase64, iv: iv);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveV2Player(String iframeUrl) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _dio.get<String>(
          iframeUrl,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 10),
            headers: const <String, dynamic>{
              'User-Agent': AppHttpClient.chromeUserAgent,
              'Referer': 'https://www.acgbibi.com/',
            },
          ),
        );
        final html = response.data;
        if (html == null || html.isEmpty) continue;

        final match = _playDataRegex.firstMatch(html);
        if (match != null && match.groupCount >= 2) {
          final cipherBase64 = match.group(1)!;
          final ivHex = match.group(2)!;
          final decrypted = decryptV2Player(cipherBase64, ivHex);
          if (decrypted != null && decrypted.isNotEmpty) {
            return decrypted;
          }
        }
      } catch (_) {
        // Retry once
      }
    }
    return null;
  }

  bool isLikelyVideoUrl(String urlStr) {
    final uri = Uri.tryParse(urlStr);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final lower = urlStr.toLowerCase();
    final cleanPath = uri.path.toLowerCase();

    const blockedExtensions = <String>[
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.svg',
      '.ico',
      '.bmp',
      '.css',
      '.js',
      '.html',
      '.htm',
      '.json',
    ];
    for (final ext in blockedExtensions) {
      if (cleanPath.endsWith(ext) &&
          !lower.contains('.m3u8') &&
          !lower.contains('/m3u8/')) {
        return false;
      }
    }

    if (lower.contains('douyin.com/note') ||
        lower.contains('bilibili.com/read') ||
        lower.contains('/danmuku') ||
        lower.contains('/danmaku') ||
        lower.contains('google-analytics')) {
      return false;
    }

    if (lower.contains('.m3u8') ||
        lower.contains('/m3u8/') ||
        lower.contains('playlist.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.flv') ||
        lower.contains('.mkv') ||
        lower.contains('.ts') ||
        lower.contains('.webm') ||
        lower.contains('.m4v')) {
      return true;
    }

    if (lower.contains('video') ||
        lower.contains('stream') ||
        lower.contains('player')) {
      return true;
    }

    return false;
  }

  Future<String?> resolve(String iframeUrl, {int depth = 0}) async {
    final cached = _resolvedCache[iframeUrl];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp).inSeconds < 300) {
      return cached.url;
    }

    final uri = Uri.tryParse(iframeUrl);
    if (uri == null) return null;

    // 1. Direct extraction from query parameters (`v=...`)
    final directV = uri.queryParameters['v'];
    if (directV != null && directV.isNotEmpty && isLikelyVideoUrl(directV)) {
      _resolvedCache[iframeUrl] = _CachedUrl(directV, DateTime.now());
      return directV;
    }

    // 2. Fast direct resolution for v2player iframes via AES-128-CBC decryption
    if (iframeUrl.contains('v2player')) {
      final directUrl = await _resolveV2Player(iframeUrl);
      if (directUrl != null && directUrl.isNotEmpty) {
        _resolvedCache[iframeUrl] = _CachedUrl(directUrl, DateTime.now());
        return directUrl;
      }
    }

    // 3. Pure-HTTP HTML/Script extraction
    final httpExtracted = await _resolveViaHttp(iframeUrl, uri, depth: depth);
    if (httpExtracted != null) {
      _resolvedCache[iframeUrl] = _CachedUrl(httpExtracted, DateTime.now());
      return httpExtracted;
    }

    // 4. WebView JS Hook fallback (Android / macOS / Windows / Fedora Linux WebKitGTK)
    if (depth == 0) {
      if (_supportsInAppWebView()) {
        final webViewResolved =
            await _resolveViaHeadlessWebView(iframeUrl, uri);
        if (webViewResolved != null && webViewResolved.isNotEmpty) {
          _resolvedCache[iframeUrl] =
              _CachedUrl(webViewResolved, DateTime.now());
          return webViewResolved;
        }
      } else if (!kIsWeb && Platform.isLinux) {
        final linuxResolved = await _resolveViaLinuxWebKitGtk(iframeUrl);
        if (linuxResolved != null && linuxResolved.isNotEmpty) {
          _resolvedCache[iframeUrl] =
              _CachedUrl(linuxResolved, DateTime.now());
          return linuxResolved;
        }
      }
    }

    return null;
  }

  /// Determines the appropriate HTTP Referer for a target player or media URL.
  static String refererForUrl(String url, {SearchSource? source}) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (source == SearchSource.acgbibi ||
        host.contains('acgbibi.com') ||
        host.contains('v2player.top') ||
        url.contains('v2player')) {
      return 'https://www.acgbibi.com/';
    }
    return 'https://www.4kvms.com/';
  }

  static const MethodChannel _linuxWebViewChannel =
      MethodChannel('com.animeget/linux_webview');

  Future<String?> _resolveViaLinuxWebKitGtk(String iframeUrl) async {
    try {
      final raw = await _linuxWebViewChannel.invokeMethod<String>(
        'resolveVideoUrl',
        <String, dynamic>{
          'url': iframeUrl,
          'referer': refererForUrl(iframeUrl),
          'userAgent': AppHttpClient.chromeUserAgent,
          'hookScript': _hookScriptSource,
          'timeoutSeconds': 30,
        },
      );
      if (raw == null || raw.isEmpty) return null;
      String? candidateUrl;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          candidateUrl = decoded['url']?.toString();
        }
      } catch (_) {
        candidateUrl = raw;
      }
      if (candidateUrl != null && isLikelyVideoUrl(candidateUrl)) {
        return candidateUrl;
      }
    } catch (_) {
      // WebKitGTK channel unavailable or failed
    }
    return null;
  }

  bool _supportsInAppWebView() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isMacOS || Platform.isWindows;
  }

  Future<String?> _resolveViaHttp(
    String iframeUrl,
    Uri uri, {
    required int depth,
  }) async {
    if (depth >= 2) return null;

    try {
      final referer = refererForUrl(iframeUrl);

      final response = await _dio.get<String>(
        iframeUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 12),
          headers: <String, dynamic>{
            'User-Agent': AppHttpClient.chromeUserAgent,
            'Referer': referer,
          },
        ),
      );
      final html = response.data;
      if (html == null || html.isEmpty) return null;

      final doc = html_parser.parse(html);
      for (final el in doc.querySelectorAll('video[src], source[src]')) {
        final src = el.attributes['src']?.trim();
        if (src != null && isLikelyVideoUrl(src)) {
          return uri.resolve(src).toString();
        }
      }

      final playerAaaaMatch =
          RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(html);
      if (playerAaaaMatch != null) {
        var rawUrl = playerAaaaMatch.group(1)!.replaceAll(r'\/', '/');
        try {
          rawUrl = Uri.decodeComponent(rawUrl);
        } catch (_) {}
        if (isLikelyVideoUrl(rawUrl)) {
          return rawUrl;
        }
      }

      for (final regex in <RegExp>[
        _hlsLoadSourceRegex,
        _artplayerUrlRegex,
        _mediaUrlRegex,
      ]) {
        for (final match in regex.allMatches(html)) {
          final candidate = match.group(regex == _mediaUrlRegex ? 0 : 1);
          if (candidate != null && isLikelyVideoUrl(candidate)) {
            return candidate;
          }
        }
      }

      for (final iframe in doc.querySelectorAll('iframe[src]')) {
        final src = iframe.attributes['src']?.trim();
        if (src == null || src.isEmpty) continue;
        final nestedUrl = uri.resolve(src).toString();
        if (nestedUrl != iframeUrl) {
          final nestedResolved =
              await _resolveViaHttp(nestedUrl, Uri.parse(nestedUrl), depth: depth + 1);
          if (nestedResolved != null) {
            return nestedResolved;
          }
        }
      }
    } catch (_) {
      // Ignore HTTP parse errors and allow WebView fallback
    }
    return null;
  }

  Future<String?> _resolveViaHeadlessWebView(String iframeUrl, Uri uri) async {
    final completer = Completer<String?>();
    Timer? timeoutTimer;
    HeadlessInAppWebView? headlessWebView;

    Future<void> finish(String? result) async {
      timeoutTimer?.cancel();
      timeoutTimer = null;
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      try {
        await headlessWebView?.dispose();
      } catch (_) {}
      headlessWebView = null;
    }

    try {
      final referer = refererForUrl(iframeUrl);

      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(iframeUrl),
          headers: <String, String>{
            'User-Agent': AppHttpClient.chromeUserAgent,
            'Referer': referer,
          },
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: AppHttpClient.chromeUserAgent,
          mediaPlaybackRequiresUserGesture: false,
          javaScriptEnabled: true,
        ),
        initialUserScripts: UnmodifiableListView<UserScript>(<UserScript>[
          UserScript(
            source: _hookScriptSource,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
        ]),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'videoCaptured',
            callback: (args) {
              if (args.isEmpty) return;
              final raw = args.first?.toString() ?? '';
              String? candidateUrl;
              try {
                final decoded = jsonDecode(raw);
                if (decoded is Map<String, dynamic>) {
                  candidateUrl = decoded['url']?.toString();
                }
              } catch (_) {
                candidateUrl = raw;
              }
              if (candidateUrl != null && isLikelyVideoUrl(candidateUrl)) {
                unawaited(finish(candidateUrl));
              }
            },
          );
        },
        onLoadResource: (controller, resource) {
          final resUrl = resource.url?.toString();
          if (resUrl != null &&
              (resUrl.contains('.m3u8') ||
                  resUrl.contains('/m3u8/') ||
                  resUrl.contains('.mp4')) &&
              isLikelyVideoUrl(resUrl)) {
            unawaited(finish(resUrl));
          }
        },
        onReceivedServerTrustAuthRequest: (controller, challenge) async {
          return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.PROCEED,
          );
        },
      );

      timeoutTimer = Timer(const Duration(seconds: 30), () {
        unawaited(finish(null));
      });

      await headlessWebView?.run();
      return await completer.future;
    } catch (_) {
      await finish(null);
      return null;
    }
  }
}
