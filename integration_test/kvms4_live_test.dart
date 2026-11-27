import 'dart:io';

import 'package:anime_get/models/anime_models.dart';
import 'package:anime_get/services/anime_source_service.dart';
import 'package:anime_get/services/http_client.dart';
import 'package:anime_get/services/ts_to_mp4_remuxer.dart';
import 'package:anime_get/services/video_url_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '4K影视 live WebView test: 大王饶命 S1E1',
    (tester) async {
      final client = AppHttpClient();
      final service = AnimeSourceService(client.dio);
      final resolver = VideoUrlResolver(client.dio);
      const source = SearchSource.kvms4;

      final results = await service.search('大王饶命', source);
      debugPrint('[kvms4] Search results: ${results.length}');
      expect(results, isNotEmpty);

      final s1 = results.firstWhere(
        (c) => c.title.trim() == '大王饶命',
        orElse: () => results.first,
      );
      debugPrint('[kvms4] Selected: ${s1.title} (${s1.link})');

      final episodes = await service.fetchEpisodes(s1);
      debugPrint('[kvms4] Episodes: ${episodes.length}');
      expect(episodes, isNotEmpty);

      final ep1 = episodes.first;
      final playUrl = '${source.baseUrl}${ep1.href}';
      debugPrint('[kvms4] Resolving via HeadlessInAppWebView: $playUrl');

      final directUrl = await resolver.resolve(playUrl);
      debugPrint('[kvms4] Resolved directUrl: $directUrl');
      expect(directUrl, isNotNull);

      final isHls = directUrl!.contains('.m3u8') ||
          directUrl.contains('playlist.m3u8') ||
          directUrl.contains('/m3u8/');

      final tempDir = Directory.systemTemp.createTempSync('animeget_kvms4_');
      try {
        final outMp4 = File('${tempDir.path}/kvms4_s1e1.mp4');
        if (isHls) {
          final referer = '${source.baseUrl}/';
          final parsed = await service.parseResolutions(
            masterUrl: directUrl,
            referer: referer,
          );
          final targetPlaylist = parsed.resolutions.isNotEmpty
              ? parsed.resolutions.first.url
              : directUrl;
          final segments = await service.parseSegmentUrls(
            playlistUrlStr: targetPlaylist,
            referer: referer,
          );
          debugPrint('[kvms4] Segments count: ${segments.length}');
          expect(segments, isNotEmpty);

          // Download first 5 segments to verify segment fetch + PNG strip + remux,
          // or full episode if fast:
          final mergedTs = File('${tempDir.path}/merged.ts');
          final sink = mergedTs.openWrite();
          var cursor = 0;
          final files = List<File?>.filled(segments.length, null);
          Future<void> worker() async {
            while (cursor < segments.length) {
              final idx = cursor++;
              final resp = await client.dio.get<List<int>>(
                segments[idx].toString(),
                options: Options(
                  responseType: ResponseType.bytes,
                  headers: const <String, dynamic>{
                    'User-Agent': AppHttpClient.chromeUserAgent,
                    'Referer': 'https://www.4kvms.com/',
                  },
                ),
              );
              expect(resp.statusCode, 200);
              final f = File('${tempDir.path}/chunk_$idx.ts');
              await f.writeAsBytes(resp.data!);
              files[idx] = f;
            }
          }

          await Future.wait(List.generate(16, (_) => worker()));
          for (final f in files) {
            sink.add(stripPngDisguiseHeader(await f!.readAsBytes()));
          }
          await sink.close();

          final ok = await TsToMp4Remuxer.remux(mergedTs, outMp4);
          debugPrint(
            '[kvms4] Remuxed=$ok, MP4 size=${outMp4.existsSync() ? outMp4.lengthSync() : 0}',
          );
          expect(ok, isTrue);
          expect(outMp4.lengthSync(), greaterThan(1024 * 1024));
        } else {
          final resp = await client.dio.download(
            directUrl,
            outMp4.path,
            options: Options(
              headers: const <String, dynamic>{
                'User-Agent': AppHttpClient.chromeUserAgent,
                'Referer': 'https://www.4kvms.com/',
              },
            ),
          );
          expect(resp.statusCode, 200);
          debugPrint('[kvms4] Downloaded MP4 size: ${outMp4.lengthSync()}');
          expect(outMp4.lengthSync(), greaterThan(1024 * 1024));
        }
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
