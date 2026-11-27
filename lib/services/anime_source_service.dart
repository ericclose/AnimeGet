import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/anime_models.dart';
import 'http_client.dart';

class PlaylistFetchResult {
  const PlaylistFetchResult({
    required this.text,
    required this.finalUri,
  });

  final String text;
  final Uri finalUri;
}

class ParsedResolutions {
  const ParsedResolutions({
    required this.resolutions,
    this.cachedText,
    this.finalUri,
  });

  final List<ResolutionOption> resolutions;
  final String? cachedText;
  final Uri? finalUri;
}

class AnimeSourceService {
  AnimeSourceService(this._dio);

  final Dio _dio;

  static const List<int> _acgbibiXorKey = <int>[
    0x4e,
    0x3f,
    0xa9,
    0xc2,
    0x12,
    0x7d,
    0x88,
    0xef,
    0x55,
    0xaa,
    0x0b,
    0xcd,
    0xde,
    0xad,
    0xbe,
    0xef,
  ];

  String _generateVerifyToken() {
    final nowMs = DateTime.now().millisecondsSinceEpoch.toString();
    final bytes = utf8.encode(nowMs);
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ _acgbibiXorKey[i % _acgbibiXorKey.length];
    }
    return base64Encode(out);
  }

  Future<void> _bypassAcgbibiSecurityIfNeeded() async {
    try {
      final token = _generateVerifyToken();
      await _dio.post<String>(
        'https://www.acgbibi.com/index.php/ajax/verify_check?type=search',
        data: 'i=${Uri.encodeQueryComponent(token)}',
        options: Options(
          contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
          responseType: ResponseType.plain,
          headers: const <String, dynamic>{
            'User-Agent': AppHttpClient.chromeUserAgent,
            'Referer': 'https://www.acgbibi.com/',
          },
        ),
      );
    } catch (_) {
      // Best-effort security verification
    }
  }

  Future<List<int>> fetchBytes(
    String url, {
    required SearchSource source,
    int retries = 3,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        final response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: <String, dynamic>{
              'User-Agent': AppHttpClient.safariUserAgent,
              'Referer': '${source.baseUrl}/',
            },
          ),
        );
        final data = response.data;
        if (data != null) return data;
      } catch (e) {
        lastError = e;
        if (attempt < retries - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
    }
    throw lastError ?? Exception('请求失败: $url');
  }

  Future<String> fetchHtml(String url, {required SearchSource source}) async {
    final bytes = await fetchBytes(url, source: source);
    var html = utf8.decode(bytes, allowMalformed: true);
    if (source == SearchSource.acgbibi && html.contains('系统安全验证')) {
      await _bypassAcgbibiSecurityIfNeeded();
      final retryBytes = await fetchBytes(url, source: source);
      html = utf8.decode(retryBytes, allowMalformed: true);
    }
    return html;
  }

  Future<List<Cartoon>> search(String query, SearchSource source) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return <Cartoon>[];
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return <Cartoon>[];
    }

    final encoded = Uri.encodeComponent(trimmed);
    switch (source) {
      case SearchSource.acgbibi:
        final url = '${source.baseUrl}/search/$encoded-------------.html';
        final html = await fetchHtml(url, source: source);
        return parseSearchResultsAcgbibi(html);
      case SearchSource.kvms4:
        final url = '${source.baseUrl}/search?q=$encoded';
        final html = await fetchHtml(url, source: source);
        return parseSearchResults4Kvms(html);
    }
  }

  Future<List<Episode>> fetchEpisodes(Cartoon cartoon) async {
    final detailUrl = cartoon.link.startsWith('/')
        ? '${cartoon.source.baseUrl}${cartoon.link}'
        : cartoon.link;
    final html = await fetchHtml(detailUrl, source: cartoon.source);
    switch (cartoon.source) {
      case SearchSource.acgbibi:
        return parseEpisodesAcgbibi(html);
      case SearchSource.kvms4:
        return parseEpisodes4Kvms(html);
    }
  }

  String extractTargetUrlToResolve({
    required String html,
    required String playUrlStr,
    required SearchSource source,
  }) {
    if (source == SearchSource.acgbibi) {
      return extractAcgbibiIframeUrl(html, playUrlStr);
    }
    return playUrlStr;
  }

  List<Cartoon> parseSearchResults4Kvms(String html) {
    final cartoons = <Cartoon>[];
    final doc = html_parser.parse(html);
    for (final item in doc.querySelectorAll('div.group')) {
      final a = item.querySelector('a[href^="/play/"]');
      if (a == null) continue;
      final link = a.attributes['href']?.trim() ?? '';
      final title = a.querySelector('h3')?.text.trim() ?? '';
      if (title.isNotEmpty && link.isNotEmpty) {
        cartoons.add(
          Cartoon(
            id: 'kvms4_$link',
            title: title,
            link: link,
            source: SearchSource.kvms4,
          ),
        );
      }
    }
    return cartoons;
  }

  List<Episode> parseEpisodes4Kvms(String html) {
    final episodes = <Episode>[];
    final doc = html_parser.parse(html);
    var epCounter = 1;
    final seenHrefs = <String>{};

    for (final link in doc.querySelectorAll('a.episode-link')) {
      final href = link.attributes['href']?.trim() ?? '';
      if (href.isEmpty || seenHrefs.contains(href)) continue;
      seenHrefs.add(href);

      var title =
          (link.querySelector('span')?.text ?? link.text).trim();
      title = title.replaceAll('\n', '').trim();
      if (title.isEmpty) {
        title = '$epCounter';
      }
      episodes.add(
        Episode(
          id: 'kvms4_ep_${epCounter}_$href',
          epNum: epCounter,
          title: title,
          href: href,
        ),
      );
      epCounter++;
    }
    return episodes;
  }

  List<Cartoon> parseSearchResultsAcgbibi(String html) {
    final cartoons = <Cartoon>[];
    final doc = html_parser.parse(html);
    final seen = <String>{};

    for (final a in doc.querySelectorAll('h4.title a')) {
      final title = a.text.trim();
      final href = a.attributes['href']?.trim() ?? '';
      if (title.isEmpty || href.isEmpty || seen.contains(href)) continue;
      seen.add(href);
      cartoons.add(
        Cartoon(
          id: 'acgbibi_$href',
          title: title,
          link: href,
          source: SearchSource.acgbibi,
        ),
      );
    }
    return cartoons;
  }

  List<Episode> parseEpisodesAcgbibi(String html) {
    final episodes = <Episode>[];
    final doc = html_parser.parse(html);

    var links = <dom.Element>[];
    final pane1 = doc.querySelector('#playlist1');
    if (pane1 != null) {
      links = pane1.querySelectorAll('a[href*="/play/"]');
    }
    if (links.isEmpty) {
      links = doc.querySelectorAll('a[href*="/play/1/"]');
    }
    if (links.isEmpty) {
      links = doc.querySelectorAll('a[href*="/play/"]').where((link) {
        final text = link.text.trim();
        return text.isNotEmpty && text != '立即播放';
      }).toList();
    }

    var epCounter = 1;
    final seenHrefs = <String>{};
    final epNumRegex = RegExp(r'/play/\d+/(\d+)\.html');

    for (final link in links) {
      final href = link.attributes['href']?.trim() ?? '';
      if (href.isEmpty || seenHrefs.contains(href)) continue;
      seenHrefs.add(href);

      var title = link.text.trim();
      if (title.isEmpty || title == '立即播放') continue;

      if (int.tryParse(title) != null) {
        title = '第$title集';
      } else if (title.endsWith('集') && !title.startsWith('第')) {
        title = '第$title';
      }

      var epNum = epCounter;
      final match = epNumRegex.firstMatch(href);
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!);
        if (parsed != null) epNum = parsed;
      }

      episodes.add(
        Episode(
          id: 'acgbibi_ep_${epNum}_$href',
          epNum: epNum,
          title: title,
          href: href,
          seasonTitle: '精品',
        ),
      );
      epCounter++;
    }
    return episodes;
  }

  String extractAcgbibiIframeUrl(String html, String playUrlStr) {
    var playerToken = '';
    var picUrl = '';
    var animeName = '';
    var nid = '1';

    final startIdx = html.indexOf('player_aaaa');
    if (startIdx >= 0) {
      final slice = html.substring(startIdx);
      final endIdx = slice.indexOf('</script>');
      final scriptText = endIdx >= 0 ? slice.substring(0, endIdx) : slice;

      final urlMatch = RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(scriptText);
      if (urlMatch != null) {
        final tokenEscaped = urlMatch.group(1)!;
        try {
          playerToken = Uri.decodeComponent(tokenEscaped);
        } catch (_) {
          playerToken = tokenEscaped;
        }
      }

      final nameMatch =
          RegExp(r'"vod_name"\s*:\s*"([^"]+)"').firstMatch(scriptText);
      if (nameMatch != null) {
        final rawName = nameMatch.group(1)!;
        try {
          animeName = jsonDecode('"$rawName"') as String;
        } catch (_) {
          animeName = rawName;
        }
      }

      final picMatch =
          RegExp(r'"vod_pic"\s*:\s*"([^"]+)"').firstMatch(scriptText);
      if (picMatch != null) {
        final rawPic = picMatch.group(1)!;
        try {
          picUrl =
              (jsonDecode('"$rawPic"') as String).replaceAll(r'\/', '/');
        } catch (_) {
          picUrl = rawPic.replaceAll(r'\/', '/');
        }
      }

      final nidMatch = RegExp(r'"nid"\s*:\s*(\d+)').firstMatch(scriptText);
      if (nidMatch != null) {
        nid = nidMatch.group(1)!;
      }
    }

    if (nid == '1') {
      final epMatch = RegExp(r'/play/\d+/(\d+)\.html').firstMatch(playUrlStr);
      if (epMatch != null) {
        nid = epMatch.group(1)!;
      }
    }

    if (playerToken.isEmpty) return playUrlStr;

    final nameEnc = Uri.encodeQueryComponent(animeName);
    final picEnc = Uri.encodeQueryComponent(picUrl);
    return 'https://art.v2player.top:8989/player/?url=$playerToken'
        '&dmid=&next=&name=$nameEnc&nid=$nid'
        '&ph=https://as.cfhls.top/&h=https://www.acgbibi.com&pic=$picEnc';
  }

  Future<PlaylistFetchResult> fetchPlaylistText(
    Uri url, {
    required String initialReferer,
  }) async {
    final candidateReferers = <String>[initialReferer];
    if (initialReferer.isNotEmpty) {
      candidateReferers.add('');
    }
    if (url.host.isNotEmpty) {
      final hostRef = 'https://${url.host}/';
      if (!candidateReferers.contains(hostRef)) {
        candidateReferers.add(hostRef);
      }
    }

    int? lastStatusCode;
    String? lastHtmlErrorHint;
    Object? lastError;

    for (final ref in candidateReferers) {
      try {
        final headers = <String, dynamic>{
          'User-Agent': AppHttpClient.chromeUserAgent,
        };
        if (ref.isNotEmpty) {
          headers['Referer'] = ref;
        }
        final response = await _dio.get<List<int>>(
          url.toString(),
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 10),
            headers: headers,
          ),
        );
        final statusCode = response.statusCode ?? 200;
        final finalUri = response.realUri;
        final bytes = response.data ?? const <int>[];
        final decodedText = utf8.decode(bytes, allowMalformed: true);

        if (statusCode == 200) {
          if (decodedText.contains('#EXTM3U') ||
              decodedText.contains('#EXTINF') ||
              decodedText.contains('#EXT-X-')) {
            return PlaylistFetchResult(text: decodedText, finalUri: finalUri);
          }
          if (decodedText.contains('<html') ||
              decodedText.contains('<!DOCTYPE')) {
            if (decodedText.contains('海外无法访问') ||
                decodedText.contains('中国大陆')) {
              lastHtmlErrorHint = '海外无法访问';
            }
            lastStatusCode = 200;
            continue;
          }
          if (decodedText.trim().isNotEmpty) {
            return PlaylistFetchResult(text: decodedText, finalUri: finalUri);
          }
        } else {
          lastStatusCode = statusCode;
          if (decodedText.contains('海外无法访问') ||
              decodedText.contains('中国大陆')) {
            lastHtmlErrorHint = '海外无法访问';
          }
        }
      } catch (e) {
        lastError = e;
      }
    }

    if (lastHtmlErrorHint == '海外无法访问') {
      throw Exception(
        '播放列表下载失败: 视频源限制仅限中国大陆 IP 访问。请检查代理或网络环境后重试。',
      );
    }
    if (lastStatusCode == 403) {
      throw Exception('播放列表下载失败 (HTTP 403): 防盗链或访问被拒绝');
    }
    if (lastStatusCode == 404) {
      throw Exception('播放列表下载失败 (HTTP 404): 资源链接不存在或已失效');
    }
    if (lastStatusCode != null) {
      throw Exception('播放列表下载失败 (HTTP $lastStatusCode)');
    }
    if (lastError != null) {
      throw Exception('播放列表下载失败: $lastError');
    }
    throw Exception('播放列表下载失败: 未能获取有效的播放列表');
  }

  Future<ParsedResolutions> parseResolutions({
    required String masterUrl,
    required String referer,
  }) async {
    final uri = Uri.tryParse(masterUrl);
    if (uri == null) {
      return const ParsedResolutions(resolutions: <ResolutionOption>[]);
    }

    try {
      final res = await fetchPlaylistText(uri, initialReferer: referer);
      final text = res.text;
      final finalUri = res.finalUri;

      if (!text.contains('#EXT-X-STREAM-INF')) {
        return ParsedResolutions(
          resolutions: <ResolutionOption>[
            ResolutionOption(width: 0, height: 0, label: '原画', url: masterUrl),
          ],
          cachedText: text,
          finalUri: finalUri,
        );
      }

      final options = <ResolutionOption>[];
      final lines = const LineSplitter().convert(text);
      final resRegex = RegExp(r'RESOLUTION=(\d+)x(\d+)');

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

        var width = 0;
        var height = 0;
        final match = resRegex.firstMatch(line);
        if (match != null) {
          width = int.tryParse(match.group(1)!) ?? 0;
          height = int.tryParse(match.group(2)!) ?? 0;
        }

        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) {
          j++;
        }
        if (j < lines.length) {
          final streamUrl = lines[j].trim();
          final absUrl = finalUri.resolve(streamUrl).toString();
          var label = '${height}P';
          if (height == 2160) {
            label = '4K';
          } else if (height == 1440) {
            label = '2K/1440P';
          }
          options.add(
            ResolutionOption(
              width: width,
              height: height,
              label: label,
              url: absUrl,
            ),
          );
        }
      }

      options.sort((a, b) => b.height.compareTo(a.height));
      return ParsedResolutions(
        resolutions: options,
        cachedText: text,
        finalUri: finalUri,
      );
    } catch (_) {
      return const ParsedResolutions(resolutions: <ResolutionOption>[]);
    }
  }

  Future<List<Uri>> parseSegmentUrls({
    required String playlistUrlStr,
    required String referer,
    String? cachedText,
    Uri? cachedFinalUri,
  }) async {
    final playlistUri = Uri.tryParse(playlistUrlStr);
    if (playlistUri == null) {
      throw Exception('播放列表 URL 无效: $playlistUrlStr');
    }

    final String text;
    final Uri finalUri;
    if (cachedText != null && cachedFinalUri != null) {
      text = cachedText;
      finalUri = cachedFinalUri;
    } else {
      final res = await fetchPlaylistText(playlistUri, initialReferer: referer);
      text = res.text;
      finalUri = res.finalUri;
    }

    if (text.contains('#EXT-X-STREAM-INF')) {
      final lines = const LineSplitter().convert(text);
      String? bestStream;
      var maxHeight = -1;
      final resRegex = RegExp(r'RESOLUTION=(\d+)x(\d+)');

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

        var height = 0;
        final match = resRegex.firstMatch(line);
        if (match != null) {
          height = int.tryParse(match.group(2)!) ?? 0;
        }
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) {
          j++;
        }
        if (j < lines.length) {
          final candidate = lines[j].trim();
          if (height > maxHeight || bestStream == null) {
            maxHeight = height;
            bestStream = candidate;
          }
        }
      }

      if (bestStream != null) {
        final subUri = finalUri.resolve(bestStream);
        return parseSegmentUrls(
          playlistUrlStr: subUri.toString(),
          referer: referer,
        );
      }
    }

    final segmentUrls = <Uri>[];
    for (final rawLine in const LineSplitter().convert(text)) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      segmentUrls.add(finalUri.resolve(trimmed));
    }

    if (segmentUrls.isEmpty) {
      throw Exception('未在播放列表中找到任何分片');
    }
    return segmentUrls;
  }
}
