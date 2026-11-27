import 'dart:convert';
import 'dart:typed_data';

import 'package:anime_get/main.dart';
import 'package:anime_get/models/anime_models.dart';
import 'package:anime_get/services/anime_source_service.dart';
import 'package:anime_get/services/download_manager.dart';
import 'package:anime_get/services/http_client.dart';
import 'package:anime_get/services/ts_to_mp4_remuxer.dart';
import 'package:anime_get/services/video_url_resolver.dart';
import 'package:anime_get/ui/theme.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AnimeSourceService parsers', () {
    late AnimeSourceService service;

    setUp(() {
      service = AnimeSourceService(AppHttpClient().dio);
    });

    test('parses 4kvms HTML search and episodes', () {
      const searchHtml = '''
      <div class="group">
        <a href="/play/999"><h3>凡人修仙传</h3></a>
      </div>
      ''';
      final cartoons = service.parseSearchResults4Kvms(searchHtml);
      expect(cartoons.length, 1);
      expect(cartoons.first.title, '凡人修仙传');
      expect(cartoons.first.link, '/play/999');

      const epHtml = '''
      <a class="episode-link" href="/play/999-1"><span>第1集</span></a>
      <a class="episode-link" href="/play/999-2"><span>第2集</span></a>
      ''';
      final eps = service.parseEpisodes4Kvms(epHtml);
      expect(eps.length, 2);
      expect(eps[0].title, '第1集');
      expect(eps[1].href, '/play/999-2');
    });

    test('parses acgbibi HTML search, episodes, and player_aaaa', () {
      const searchHtml = '''
      <h4 class="title"><a href="/bangumi/888.html">灵笼</a></h4>
      ''';
      final cartoons = service.parseSearchResultsAcgbibi(searchHtml);
      expect(cartoons.length, 1);
      expect(cartoons.first.title, '灵笼');

      const epHtml = '''
      <div id="playlist1">
        <a href="/play/888/1.html">1</a>
        <a href="/play/888/2.html">2集</a>
      </div>
      ''';
      final eps = service.parseEpisodesAcgbibi(epHtml);
      expect(eps.length, 2);
      expect(eps[0].title, '第1集');
      expect(eps[1].title, '第2集');

      const playHtml = '''
      <script>
        var player_aaaa={"url":"token123","vod_name":"灵笼","vod_pic":"https:\\/\\/img.test\\/a.jpg","nid":5};
      </script>
      ''';
      final iframeUrl = service.extractAcgbibiIframeUrl(
        playHtml,
        'https://www.acgbibi.com/play/888/5.html',
      );
      expect(
        iframeUrl,
        startsWith('https://art.v2player.top:8989/player/?url=token123'),
      );
      expect(iframeUrl, contains('nid=5'));
    });
  });

  group('VideoUrlResolver', () {
    test('decrypts v2player AES-128-CBC payload', () {
      final resolver = VideoUrlResolver(AppHttpClient().dio);
      final key = encrypt.Key.fromUtf8('ABABEF777999CCCD');
      final ivBytes = List<int>.generate(16, (i) => i);
      final ivHex =
          ivBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );
      const expected = 'https://cdn.example.com/video/index.m3u8';
      final encrypted =
          encrypter.encrypt(expected, iv: encrypt.IV(Uint8List.fromList(ivBytes)));

      final decrypted = resolver.decryptV2Player(encrypted.base64, ivHex);
      expect(decrypted, expected);
    });

    test('filters non-video URLs accurately', () {
      final resolver = VideoUrlResolver(AppHttpClient().dio);
      expect(resolver.isLikelyVideoUrl('https://a.com/index.m3u8'), isTrue);
      expect(resolver.isLikelyVideoUrl('https://a.com/cover.jpg'), isFalse);
      expect(resolver.isLikelyVideoUrl('https://a.com/danmaku/list'), isFalse);
    });
  });

  group('TsToMp4Remuxer & Filename helpers', () {
    test('strips PNG disguise header before TS sync byte', () {
      final fake = Uint8List(73 + 188 * 3);
      fake[0] = 0x89;
      fake[1] = 0x50;
      fake[2] = 0x4e;
      fake[3] = 0x47;
      fake[4] = 0x0d;
      fake[5] = 0x0a;
      fake[6] = 0x1a;
      fake[7] = 0x0a;
      fake[73] = 0x47;
      fake[73 + 188] = 0x47;
      fake[73 + 188 * 2] = 0x47;

      final stripped = stripPngDisguiseHeader(fake);
      expect(stripped.length, 188 * 3);
      expect(stripped[0], 0x47);
    });

    test('cleans title and generates valid video filename', () {
      final name = DownloadManager.generateVideoFilename(
        cartoonTitle: '凡人修仙传 1080P版 [4K影视]',
        seasonTitle: '4K影视',
        episodeTitle: '第01集',
        resolutionLabel: ' 1080P',
      );
      expect(name, '凡人修仙传 - 第01集 1080P');
    });

    test('persists and restores DownloadTask JSON across restarts', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final task = DownloadTask(
        id: 't_1',
        cartoonTitle: '大王饶命',
        episodeNum: 1,
        episodeTitle: '第01集',
        episode: Episode(
          id: 'ep_1',
          epNum: 1,
          title: '第01集',
          href: '/play/ch4u9or2w',
        ),
        source: SearchSource.kvms4,
      );
      task.setDownloading(completed: 12, total: 100);

      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.id, 't_1');
      expect(restored.cartoonTitle, '大王饶命');
      expect(restored.source, SearchSource.kvms4);
      // In-flight downloading tasks restore as paused on app restart
      expect(restored.phase, DownloadPhase.paused);
      expect(restored.completedCount, 12);
      expect(restored.totalCount, 100);
    });

    test('parses Content-Range and splits MP4 into contiguous byte ranges', () {
      expect(
        DownloadManager.parseTotalBytesFromContentRange('bytes 0-0/10485760'),
        10485760,
      );
      expect(
        DownloadManager.parseTotalBytesFromContentRange('bytes */1024'),
        isNull,
      );

      final ranges = DownloadManager.buildByteRanges(20 * 1024 * 1024, 16);
      expect(ranges.length, greaterThanOrEqualTo(16));
      expect(ranges.first.$1, 0);
      expect(ranges.last.$2, 20 * 1024 * 1024 - 1);
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].$1, ranges[i - 1].$2 + 1);
      }
    });

    test('tracks and resets activeConnections on DownloadTask', () {
      final task = DownloadTask(
        id: 't_conn',
        cartoonTitle: '测试',
        episodeNum: 1,
        episodeTitle: '第1集',
        episode: Episode(
          id: 'ep_1',
          epNum: 1,
          title: '第1集',
          href: '/play/1',
        ),
      );
      expect(task.activeConnections, 0);
      task.incrementActiveConnections();
      task.incrementActiveConnections();
      expect(task.activeConnections, 2);
      task.decrementActiveConnections();
      expect(task.activeConnections, 1);
      task.setPaused();
      expect(task.activeConnections, 0);
    });

    test('remuxes minimal MPEG-TS H.264 stream into valid MP4 boxes', () {
      final tsPackets = BytesBuilder();

      Uint8List makeTsPacket(int pid, bool pusi, List<int> payload) {
        final pkt = Uint8List(188);
        pkt[0] = 0x47;
        pkt[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
        pkt[2] = pid & 0xFF;
        pkt[3] = 0x10; // payload only
        final copyLen = payload.length < 184 ? payload.length : 184;
        for (var i = 0; i < copyLen; i++) {
          pkt[4 + i] = payload[i];
        }
        for (var i = 4 + copyLen; i < 188; i++) {
          pkt[i] = 0xFF;
        }
        return pkt;
      }

      // PAT: program 1 -> PMT PID 0x100
      tsPackets.add(makeTsPacket(0x0000, true, <int>[
        0x00, // pointer_field
        0x00, 0xB0, 0x0D, // table_id=0, section_len=13
        0x00, 0x01, 0xC1, 0x00, 0x00,
        0x00, 0x01, 0xE1, 0x00, // prog 1 -> PID 0x0100
        0x00, 0x00, 0x00, 0x00,
      ]));

      // PMT: H.264 (0x1B) on PID 0x0101
      tsPackets.add(makeTsPacket(0x0100, true, <int>[
        0x00, // pointer_field
        0x02, 0xB0, 0x12, // table_id=2, section_len=18
        0x00, 0x01, 0xC1, 0x00, 0x00,
        0xE1, 0x01, 0xF0, 0x00,
        0x1B, 0xE1, 0x01, 0xF0, 0x00, // H.264 PID 0x0101
        0x00, 0x00, 0x00, 0x00,
      ]));

      // Video PES with SPS, PPS, IDR NALU
      tsPackets.add(makeTsPacket(0x0101, true, <int>[
        0x00, 0x00, 0x01, 0xE0, 0x00, 0x00, 0x80, 0x80, 0x05,
        0x21, 0x00, 0x01, 0x00, 0x01, // PTS=0
        0x00, 0x00, 0x00, 0x01, 0x67, 0x64, 0x00, 0x1F, // SPS
        0x00, 0x00, 0x00, 0x01, 0x68, 0xEE, 0x3C, 0x80, // PPS
        0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x21, // IDR
      ]));

      final mp4 = TsToMp4Remuxer.remuxBytes(tsPackets.takeBytes());
      expect(mp4, isNotNull);
      expect(utf8.decode(mp4!.sublist(4, 8)), 'ftyp');
      final decodedStr = latin1.decode(mp4);
      expect(decodedStr, contains('mdat'));
      expect(decodedStr, contains('moov'));
      expect(decodedStr, contains('avcC'));
    });

    test('parses H.264 SPS dimensions with cropping accurately', () {
      // High profile 1920x1080 (120x68 macroblocks, crop_bottom=4 -> 1088-8=1080)
      final sps1080p = Uint8List.fromList(<int>[
        0x67, 0x64, 0x00, 0x28, 0xAC, 0xD9, 0x40, 0x78,
        0x02, 0x27, 0xE5, 0xC0, 0x44, 0x00, 0x00, 0x03,
        0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0xC0, 0x3C,
        0x60, 0xC6, 0x58,
      ]);
      expect(TsToMp4Remuxer.parseSpsDimensions(sps1080p), (1920, 1080));

      // High profile 1280x720 (80x45 macroblocks, no crop)
      final sps720p = Uint8List.fromList(<int>[
        0x67, 0x64, 0x00, 0x1F, 0xAC, 0xD9, 0x40, 0x50,
        0x05, 0xBB, 0x01, 0x10, 0x00, 0x00, 0x03, 0x00,
        0x10, 0x00, 0x00, 0x03, 0x03, 0x00, 0xF1, 0x83,
        0x19, 0x60,
      ]);
      expect(TsToMp4Remuxer.parseSpsDimensions(sps720p), (1280, 720));
    });
  });

  testWidgets('AnimeGetApp renders openwrt-style dashboard UI', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(AppTheme.colorByTitle('大王饶命'), AppTheme.colorByTitle('大王饶命'));
    await tester.pumpWidget(const AnimeGetApp());
    await tester.pump();
    expect(find.text('AnimeGet'), findsOneWidget);
    expect(find.text('4K影视'), findsOneWidget);
    expect(find.text('acgbibi【精品】'), findsOneWidget);
  });

  testWidgets('AnimeGetApp renders mobile tabs cleanly without overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'search_history': <String>['大王饶命', '时光代理人'],
    });
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AnimeGetApp());
    await tester.pumpAndSettle();
    expect(find.text('搜索动漫名称，如 大王饶命'), findsOneWidget);

    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    expect(find.text('暂停/异常'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('系统设置'), findsOneWidget);
    expect(find.text('主题外观'), findsOneWidget);
    expect(find.text('更改目录'), findsOneWidget);

    // System back from Settings returns to Search tab instead of exiting
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('搜索动漫名称，如 大王饶命'), findsOneWidget);

    // First back at root shows double-back exit prompt
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('再按一次返回桌面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
