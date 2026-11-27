import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/anime_models.dart';
import 'anime_source_service.dart';
import 'http_client.dart';
import 'ts_to_mp4_remuxer.dart';
import 'video_url_resolver.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager({
    AppHttpClient? httpClient,
  }) : _httpClient = httpClient ?? AppHttpClient() {
    _sourceService = AnimeSourceService(_httpClient.dio);
    _urlResolver = VideoUrlResolver(_httpClient.dio);
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateSpeed();
    });
    _loadSettings();
  }

  static const MethodChannel _mediaChannel =
      MethodChannel('com.animeget/media_remux');
  static const String _tasksStorageKey = 'download_tasks_v1';

  final AppHttpClient _httpClient;
  late final AnimeSourceService _sourceService;
  late final VideoUrlResolver _urlResolver;

  SearchSource _selectedSource = SearchSource.kvms4;
  SearchSource get selectedSource => _selectedSource;

  String searchQuery = '';
  bool isSearching = false;
  List<Cartoon> searchResults = <Cartoon>[];
  Cartoon? selectedCartoon;

  bool isFetchingEpisodes = false;
  List<Episode> episodes = <Episode>[];
  final Set<int> selectedEpisodes = <int>{};

  bool isFetchingResolutions = false;
  List<ResolutionOption> resolutionOptions = <ResolutionOption>[];
  int? _selectedResolutionHeight;
  int? get selectedResolutionHeight => _selectedResolutionHeight;

  int _maxWorkers = 16;
  int get maxWorkers => _maxWorkers;

  int _maxConcurrentDownloads = 3;
  int get maxConcurrentDownloads => _maxConcurrentDownloads;

  ThemeMode themeMode = ThemeMode.system;
  List<String> searchHistory = <String>[];

  String _downloadDirectoryPath = '';
  String get downloadDirectoryPath => _downloadDirectoryPath;

  final List<DownloadTask> downloadTasks = <DownloadTask>[];
  final Map<String, CancelToken> _activeCancelTokens = <String, CancelToken>{};

  int _bytesDownloadedThisSecond = 0;
  double currentDownloadSpeed = 0.0;
  Timer? _speedTimer;
  Timer? _persistDebounceTimer;

  String get currentDownloadSpeedString => formatSpeed(currentDownloadSpeed);

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _maxWorkers = prefs.getInt('maxWorkers') ?? 16;
    _maxConcurrentDownloads = prefs.getInt('maxConcurrentDownloads') ?? 3;
    final savedHeight = prefs.getInt('selectedResolutionHeight');
    _selectedResolutionHeight =
        (savedHeight != null && savedHeight > 0) ? savedHeight : null;
    final savedTheme = prefs.getString('themeMode');
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == savedTheme,
      orElse: () => ThemeMode.system,
    );
    searchHistory =
        prefs.getStringList('searchHistory') ?? <String>[];

    final savedDir = prefs.getString('downloadDirectoryPath');
    if (savedDir != null && savedDir.isNotEmpty && Directory(savedDir).existsSync()) {
      _downloadDirectoryPath = savedDir;
    } else {
      _downloadDirectoryPath = await _resolveDefaultDownloadDirectory();
    }

    final savedTasksJson = prefs.getString(_tasksStorageKey);
    if (savedTasksJson != null && savedTasksJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedTasksJson);
        if (decoded is List) {
          downloadTasks.clear();
          for (final item in decoded) {
            if (item is Map) {
              final task = DownloadTask.fromJson(item.cast<String, dynamic>());
              task.addListener(_schedulePersistTasks);
              downloadTasks.add(task);
            }
          }
        }
      } catch (e) {
        debugPrint('Restore download tasks failed: $e');
      }
    }

    notifyListeners();
    checkAndRunQueue();
  }

  void _schedulePersistTasks() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(persistTasksNow());
    });
  }

  Future<void> persistTasksNow() async {
    _persistDebounceTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(
        downloadTasks.map((t) => t.toJson()).toList(),
      );
      await prefs.setString(_tasksStorageKey, payload);
    } catch (e) {
      debugPrint('Persist download tasks failed: $e');
    }
  }

  Future<bool> openInFileManager([String? targetPath]) async {
    final rawPath = (targetPath != null && targetPath.isNotEmpty)
        ? targetPath
        : _downloadDirectoryPath;
    if (rawPath.isEmpty) return false;

    try {
      if (Platform.isMacOS) {
        if (File(rawPath).existsSync()) {
          final res = await Process.run('open', <String>['-R', rawPath]);
          return res.exitCode == 0;
        }
        final dir = File(rawPath).parent.existsSync()
            ? File(rawPath).parent.path
            : _downloadDirectoryPath;
        final res = await Process.run('open', <String>[dir]);
        return res.exitCode == 0;
      }
      if (Platform.isWindows) {
        if (File(rawPath).existsSync()) {
          final res =
              await Process.run('explorer', <String>['/select,$rawPath']);
          return res.exitCode == 0;
        }
        final dir = Directory(rawPath).existsSync()
            ? rawPath
            : File(rawPath).parent.path;
        final res = await Process.run('explorer', <String>[dir]);
        return res.exitCode == 0;
      }
      if (Platform.isLinux) {
        final dir = Directory(rawPath).existsSync()
            ? rawPath
            : File(rawPath).parent.path;
        final res = await Process.run('xdg-open', <String>[dir]);
        return res.exitCode == 0;
      }
      if (Platform.isAndroid) {
        final dirPath = File(rawPath).existsSync() && File(rawPath).statSync().type == FileSystemEntityType.file
            ? File(rawPath).parent.path
            : rawPath;
        final ok = await _mediaChannel.invokeMethod<bool>(
          'openFolder',
          <String, String>{'path': dirPath},
        );
        return ok ?? false;
      }
    } catch (e) {
      debugPrint('Open in file manager failed: $e');
    }
    return false;
  }

  Future<bool> openVideoFile([String? targetPath]) async {
    if (targetPath == null || targetPath.isEmpty) return false;
    try {
      if (Platform.isMacOS) {
        final res = await Process.run('open', <String>[targetPath]);
        return res.exitCode == 0;
      }
      if (Platform.isWindows) {
        final res = await Process.run(
          'cmd',
          <String>['/c', 'start', '', targetPath],
        );
        return res.exitCode == 0;
      }
      if (Platform.isLinux) {
        final res = await Process.run('xdg-open', <String>[targetPath]);
        return res.exitCode == 0;
      }
      if (Platform.isAndroid) {
        final ok = await _mediaChannel.invokeMethod<bool>(
          'openFile',
          <String, String>{'path': targetPath},
        );
        return ok ?? false;
      }
    } catch (e) {
      debugPrint('Open video file failed: $e');
    }
    return false;
  }

  Future<String> _resolveDefaultDownloadDirectory() async {
    try {
      if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) return downloads.path;
      }
      if (!kIsWeb && Platform.isAndroid) {
        const androidDefault = '/sdcard/Download/acg';
        final target = Directory(androidDefault);
        try {
          if (!target.existsSync()) {
            target.createSync(recursive: true);
          }
          return target.path;
        } catch (_) {
          // Fall back to app documents directory if public Download is inaccessible.
        }
      }
      final appDoc = await getApplicationDocumentsDirectory();
      final target = Directory('${appDoc.path}${Platform.pathSeparator}AnimeGet');
      if (!target.existsSync()) {
        target.createSync(recursive: true);
      }
      return target.path;
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.name);
  }

  Future<void> cycleThemeMode() async {
    final next = switch (themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setThemeMode(next);
  }

  Future<void> _recordSearchHistory(String query) async {
    searchHistory.remove(query);
    searchHistory.insert(0, query);
    if (searchHistory.length > 10) {
      searchHistory = searchHistory.sublist(0, 10);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('searchHistory', searchHistory);
  }

  Future<void> removeSearchHistoryItem(String query) async {
    searchHistory.remove(query);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('searchHistory', searchHistory);
  }

  Future<void> clearSearchHistory() async {
    searchHistory.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('searchHistory');
  }

  Future<void> setMaxWorkers(int value) async {
    _maxWorkers = value.clamp(1, 64);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maxWorkers', _maxWorkers);
  }

  Future<void> setMaxConcurrentDownloads(int value) async {
    _maxConcurrentDownloads = value.clamp(1, 8);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maxConcurrentDownloads', _maxConcurrentDownloads);
    checkAndRunQueue();
  }

  Future<void> setSelectedResolutionHeight(int? height) async {
    _selectedResolutionHeight = height;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (height != null) {
      await prefs.setInt('selectedResolutionHeight', height);
    } else {
      await prefs.remove('selectedResolutionHeight');
    }
  }

  Future<void> setDownloadDirectory(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _downloadDirectoryPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('downloadDirectoryPath', path);
  }

  void changeSource(SearchSource newSource) {
    if (_selectedSource == newSource) return;
    _selectedSource = newSource;
    searchResults = <Cartoon>[];
    selectedCartoon = null;
    episodes = <Episode>[];
    selectedEpisodes.clear();
    resolutionOptions = <ResolutionOption>[];
    _selectedResolutionHeight = null;
    notifyListeners();
  }

  Future<void> performSearch([String? overrideQuery]) async {
    if (overrideQuery != null) {
      searchQuery = overrideQuery;
    }
    final trimmed = searchQuery.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return;
    }

    isSearching = true;
    searchResults = <Cartoon>[];
    selectedCartoon = null;
    episodes = <Episode>[];
    selectedEpisodes.clear();
    resolutionOptions = <ResolutionOption>[];
    notifyListeners();
    unawaited(_recordSearchHistory(trimmed));

    try {
      searchResults = await _sourceService.search(trimmed, _selectedSource);
    } catch (e) {
      debugPrint('Search failed: $e');
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  Future<void> selectCartoon(Cartoon cartoon) async {
    selectedCartoon = cartoon;
    isFetchingEpisodes = true;
    episodes = <Episode>[];
    selectedEpisodes.clear();
    resolutionOptions = <ResolutionOption>[];
    _selectedResolutionHeight = null;
    notifyListeners();

    try {
      episodes = await _sourceService.fetchEpisodes(cartoon);
      if (episodes.isNotEmpty) {
        await fetchResolutionOptions(episodes.first);
      }
    } catch (e) {
      debugPrint('Fetch episodes failed: $e');
    } finally {
      isFetchingEpisodes = false;
      notifyListeners();
    }
  }

  Future<void> updateResolutionOptionsForSeason(String seasonTitle) async {
    final seasonEps =
        episodes.where((ep) => ep.seasonTitle == seasonTitle).toList();
    if (seasonEps.isNotEmpty) {
      await fetchResolutionOptions(seasonEps.first);
    }
  }

  Future<String?> _resolveEpisodeDirectUrl(
    Episode episode,
    SearchSource source, {
    void Function(String stage)? onStage,
  }) async {
    if (_isDirectMediaHref(episode.href)) {
      return episode.href;
    }
    final playUrlStr = episode.href.startsWith('/')
        ? '${source.baseUrl}${episode.href}'
        : episode.href;
    final html = await _sourceService.fetchHtml(playUrlStr, source: source);
    final targetUrl = _sourceService.extractTargetUrlToResolve(
      html: html,
      playUrlStr: playUrlStr,
      source: source,
    );
    if (targetUrl.isEmpty) return null;
    onStage?.call('正在解析直链...');
    return _urlResolver.resolve(targetUrl);
  }

  Future<void> fetchResolutionOptions(Episode episode) async {
    final cartoon = selectedCartoon;
    if (cartoon == null) return;

    isFetchingResolutions = true;
    resolutionOptions = <ResolutionOption>[];
    notifyListeners();

    try {
      final directUrl = await _resolveEpisodeDirectUrl(episode, cartoon.source);
      if (directUrl != null && directUrl.isNotEmpty) {
        if (_isHlsUrl(directUrl)) {
          final referer = VideoUrlResolver.refererForUrl(
            directUrl,
            source: cartoon.source,
          );
          final parsed = await _sourceService.parseResolutions(
            masterUrl: directUrl,
            referer: referer,
          );
          resolutionOptions = parsed.resolutions;
        } else {
          resolutionOptions = <ResolutionOption>[
            ResolutionOption(width: 0, height: 0, label: '原画', url: directUrl),
          ];
        }
      }
    } catch (e) {
      debugPrint('Fetch resolutions failed: $e');
    } finally {
      isFetchingResolutions = false;
      notifyListeners();
    }
  }

  void clearSelectedCartoon() {
    selectedCartoon = null;
    episodes = <Episode>[];
    selectedEpisodes.clear();
    resolutionOptions = <ResolutionOption>[];
    notifyListeners();
  }

  void toggleEpisodeSelection(int epNum) {
    if (selectedEpisodes.contains(epNum)) {
      selectedEpisodes.remove(epNum);
    } else {
      selectedEpisodes.add(epNum);
    }
    notifyListeners();
  }

  void selectAllEpisodes([List<Episode>? subset]) {
    final target = subset ?? episodes;
    selectedEpisodes.addAll(target.map((e) => e.epNum));
    notifyListeners();
  }

  void deselectAllEpisodes() {
    selectedEpisodes.clear();
    notifyListeners();
  }

  void startDownloads() {
    final cartoon = selectedCartoon;
    if (cartoon == null || selectedEpisodes.isEmpty) return;

    final sortedNums = selectedEpisodes.toList()..sort();
    for (final num in sortedNums) {
      final ep = episodes.where((e) => e.epNum == num).firstOrNull;
      if (ep == null) continue;
      final taskId =
          '${DateTime.now().microsecondsSinceEpoch}_${ep.epNum}_${cartoon.id.hashCode}';
      final task = DownloadTask(
        id: taskId,
        cartoonTitle: cartoon.title,
        episodeNum: ep.epNum,
        episodeTitle: ep.title,
        episode: ep,
        source: cartoon.source,
      );
      task.addListener(_schedulePersistTasks);
      downloadTasks.add(task);
    }
    notifyListeners();
    unawaited(persistTasksNow());
    checkAndRunQueue();
  }

  void checkAndRunQueue() {
    while (true) {
      final runningCount = downloadTasks.where((t) => t.isActive).length;
      if (runningCount >= _maxConcurrentDownloads) break;

      final nextTask = downloadTasks
          .where((t) => t.phase == DownloadPhase.queued && !t.isCancelled)
          .firstOrNull;
      if (nextTask == null) break;

      nextTask.setParsing('正在解析网页播放源...');
      unawaited(
        _performDownload(nextTask).whenComplete(checkAndRunQueue),
      );
    }
  }

  void pauseTask(DownloadTask task) {
    _activeCancelTokens[task.id]?.cancel('paused');
    _activeCancelTokens.remove(task.id);
    task.setPaused();
    checkAndRunQueue();
  }

  void resumeTask(DownloadTask task) {
    if (task.phase == DownloadPhase.paused) {
      task.setQueued();
      checkAndRunQueue();
    }
  }

  void retryTask(DownloadTask task) {
    if (task.phase == DownloadPhase.failed) {
      task.setQueued();
      checkAndRunQueue();
    }
  }

  void cancelTask(DownloadTask task) {
    task.isCancelled = true;
    _activeCancelTokens[task.id]?.cancel('cancelled');
    _activeCancelTokens.remove(task.id);
    task.setFailed('已取消');
    checkAndRunQueue();
  }

  void deleteTask(DownloadTask task, {bool deleteFile = false}) {
    deleteTasks(<DownloadTask>[task], deleteFile: deleteFile);
  }

  void deleteTasks(Iterable<DownloadTask> tasks, {bool deleteFile = false}) {
    final toRemoveIds = <String>{};
    for (final task in tasks) {
      toRemoveIds.add(task.id);
      _activeCancelTokens[task.id]?.cancel('deleted');
      _activeCancelTokens.remove(task.id);
      task.removeListener(_schedulePersistTasks);
      final tempDir = Directory(_taskTempDirPath(task.id));
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
      if (deleteFile && task.outputPath != null && task.outputPath!.isNotEmpty) {
        final outFile = File(task.outputPath!);
        if (outFile.existsSync()) {
          try {
            outFile.deleteSync();
          } catch (_) {}
        }
      }
    }
    if (toRemoveIds.isEmpty) return;
    downloadTasks.removeWhere((t) => toRemoveIds.contains(t.id));
    notifyListeners();
    unawaited(persistTasksNow());
    checkAndRunQueue();
  }

  void pauseAllTasks() {
    for (final task in downloadTasks) {
      if (task.isActive || task.phase == DownloadPhase.queued) {
        _activeCancelTokens[task.id]?.cancel('paused');
        _activeCancelTokens.remove(task.id);
        task.setPaused();
      }
    }
    notifyListeners();
    unawaited(persistTasksNow());
  }

  void resumeAllTasks() {
    for (final task in downloadTasks) {
      if (task.phase == DownloadPhase.paused) {
        task.setQueued();
      }
    }
    notifyListeners();
    unawaited(persistTasksNow());
    checkAndRunQueue();
  }

  void clearCompletedTasks() {
    final completed = downloadTasks
        .where((t) => t.phase == DownloadPhase.completed)
        .toList();
    for (final task in completed) {
      task.removeListener(_schedulePersistTasks);
      downloadTasks.remove(task);
    }
    notifyListeners();
    unawaited(persistTasksNow());
  }

  String _taskTempDirPath(String taskId) {
    return '$_downloadDirectoryPath${Platform.pathSeparator}temp_$taskId';
  }

  Future<void> _performDownload(DownloadTask task) async {
    if (_downloadDirectoryPath.isEmpty) {
      _downloadDirectoryPath = await _resolveDefaultDownloadDirectory();
    }

    final cancelToken = CancelToken();
    _activeCancelTokens[task.id] = cancelToken;

    try {
      final directUrl = await _resolveEpisodeDirectUrl(
        task.episode,
        task.source,
        onStage: task.setParsing,
      );

      if (task.isCancelled || cancelToken.isCancelled) return;
      if (directUrl == null || directUrl.isEmpty) {
        task.setFailed('获取播放地址失败');
        return;
      }

      task.resolvedUrl = directUrl;
      task.playlistUrl = directUrl;
      task.setParsing('正在获取清晰度与播放列表...');

      if (!_isHlsUrl(directUrl)) {
        await _downloadDirectMp4(task, directUrl, cancelToken);
        return;
      }

      final downloadReferer = VideoUrlResolver.refererForUrl(
        directUrl,
        source: task.source,
      );
      final parsedRes = await _sourceService.parseResolutions(
        masterUrl: directUrl,
        referer: downloadReferer,
      );

      var targetPlaylistUrl = directUrl;
      var resolutionLabel = '';
      if (parsedRes.resolutions.isNotEmpty) {
        ResolutionOption chosen;
        final targetHeight = _selectedResolutionHeight;
        if (targetHeight != null) {
          chosen = parsedRes.resolutions.firstWhere(
            (r) => r.height == targetHeight,
            orElse: () => parsedRes.resolutions.reduce(
              (a, b) =>
                  (a.height - targetHeight).abs() <
                          (b.height - targetHeight).abs()
                      ? a
                      : b,
            ),
          );
        } else {
          chosen = parsedRes.resolutions.first;
        }
        targetPlaylistUrl = chosen.url;
        task.playlistUrl = chosen.url;
        if (chosen.height > 0) {
          resolutionLabel = ' ${chosen.label}';
        }
      }

      task.setParsing('正在解析分片地址...');
      final segmentUrls = await _sourceService.parseSegmentUrls(
        playlistUrlStr: targetPlaylistUrl,
        referer: downloadReferer,
        cachedText: targetPlaylistUrl == directUrl ? parsedRes.cachedText : null,
        cachedFinalUri:
            targetPlaylistUrl == directUrl ? parsedRes.finalUri : null,
      );

      if (task.isCancelled || cancelToken.isCancelled) return;

      final totalSegments = segmentUrls.length;
      final tempDir = Directory(_taskTempDirPath(task.id));
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }

      final initialStates = List<SegmentState>.generate(totalSegments, (idx) {
        final chunkFile =
            File('${tempDir.path}${Platform.pathSeparator}chunk_$idx.ts');
        if (chunkFile.existsSync() && chunkFile.lengthSync() > 0) {
          return SegmentState.downloaded;
        }
        return SegmentState.pending;
      });

      final initialCompleted =
          initialStates.where((s) => s == SegmentState.downloaded).length;
      task.setSegmentsStatus(initialStates);
      task.setDownloading(completed: initialCompleted, total: totalSegments);

      final segReferer = _determineSegmentReferer(
        task.source,
        segmentUrls.first.toString(),
      );

      // Concurrent worker pool using Dio
      final pendingIndices = <int>[
        for (var i = 0; i < totalSegments; i++)
          if (initialStates[i] != SegmentState.downloaded) i,
      ];

      await _downloadSegmentsConcurrently(
        task: task,
        segmentUrls: segmentUrls,
        indices: pendingIndices,
        tempDir: tempDir,
        referer: segReferer,
        cancelToken: cancelToken,
      );

      if (task.isCancelled) {
        task.setFailed('已取消下载');
        return;
      }
      if (task.phase == DownloadPhase.paused) return;

      // Retry failed segments up to 2 rounds
      for (var round = 0; round < 2; round++) {
        final failedIndices = <int>[
          for (var i = 0; i < totalSegments; i++)
            if (task.segmentsStatus[i] != SegmentState.downloaded) i,
        ];
        if (failedIndices.isEmpty) break;
        await Future<void>.delayed(const Duration(seconds: 1));
        if (task.isCancelled || task.phase == DownloadPhase.paused) return;

        await _downloadSegmentsConcurrently(
          task: task,
          segmentUrls: segmentUrls,
          indices: failedIndices,
          tempDir: tempDir,
          referer: segReferer,
          cancelToken: cancelToken,
        );
      }

      if (task.isCancelled) {
        task.setFailed('已取消下载');
        return;
      }
      if (task.phase == DownloadPhase.paused) return;

      final remainingFailed = task.segmentsStatus
          .where((s) => s != SegmentState.downloaded)
          .length;
      if (remainingFailed > 0) {
        task.setFailed('有 $remainingFailed 个分片下载失败，点击可重试');
        return;
      }

      // Merge segments and strip PNG disguise headers
      task.setMerging(completed: 0, total: totalSegments);
      final baseName = generateVideoFilename(
        cartoonTitle: task.cartoonTitle,
        seasonTitle: task.episode.seasonTitle,
        episodeTitle: task.episode.title,
        resolutionLabel: resolutionLabel,
      );
      final tsPath = '$_downloadDirectoryPath${Platform.pathSeparator}$baseName.ts';
      final tsFile = File(tsPath);
      if (tsFile.existsSync()) tsFile.deleteSync();

      final sink = tsFile.openWrite();
      try {
        for (var idx = 0; idx < totalSegments; idx++) {
          if (task.isCancelled) break;
          final chunkFile =
              File('${tempDir.path}${Platform.pathSeparator}chunk_$idx.ts');
          if (chunkFile.existsSync()) {
            final rawBytes = await chunkFile.readAsBytes();
            final cleanBytes = stripPngDisguiseHeader(rawBytes);
            sink.add(cleanBytes);
            try {
              chunkFile.deleteSync();
            } catch (_) {}
          }
          if (idx % 10 == 0 || idx == totalSegments - 1) {
            task.setMerging(completed: idx + 1, total: totalSegments);
          }
        }
      } finally {
        await sink.close();
      }

      if (task.isCancelled) {
        if (tsFile.existsSync()) tsFile.deleteSync();
        task.setFailed('已取消下载');
        return;
      }

      // Remux TS -> MP4
      task.setRemuxing();
      final mp4Path =
          '$_downloadDirectoryPath${Platform.pathSeparator}$baseName.mp4';
      final mp4File = File(mp4Path);
      if (mp4File.existsSync()) mp4File.deleteSync();

      var remuxed = false;
      if (!kIsWeb && Platform.isAndroid) {
        remuxed = await _remuxWithAndroidMedia3(tsPath, mp4Path);
      }
      if (!remuxed) {
        remuxed = await TsToMp4Remuxer.remux(tsFile, mp4File);
      }

      if (remuxed && mp4File.existsSync() && mp4File.lengthSync() > 0) {
        try {
          tsFile.deleteSync();
        } catch (_) {}
        task.setCompleted(mp4Path);
      } else {
        task.setCompleted(tsPath);
      }

      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      if (task.phase != DownloadPhase.paused && !task.isCancelled) {
        task.setFailed(e.toString());
      }
    } finally {
      _activeCancelTokens.remove(task.id);
    }
  }

  Future<bool> _remuxWithAndroidMedia3(String tsPath, String mp4Path) async {
    try {
      final result = await _mediaChannel.invokeMethod<bool>(
        'remuxTsToMp4',
        <String, String>{
          'inputPath': tsPath,
          'outputPath': mp4Path,
        },
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static int? parseTotalBytesFromContentRange(String? contentRange) {
    if (contentRange == null || contentRange.isEmpty) return null;
    final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(contentRange);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static List<(int start, int end)> buildByteRanges(
    int totalBytes,
    int workerCount,
  ) {
    if (totalBytes <= 0) return const <(int, int)>[];
    const minChunkBytes = 512 * 1024; // 512 KB
    const targetChunkBytes = 2 * 1024 * 1024; // 2 MB
    final desiredChunks = max(
      workerCount,
      (totalBytes / targetChunkBytes).ceil(),
    ).clamp(1, 256);
    final chunkSize = max(
      minChunkBytes,
      (totalBytes / desiredChunks).ceil(),
    );

    final ranges = <(int, int)>[];
    var start = 0;
    while (start < totalBytes) {
      final end = min(start + chunkSize - 1, totalBytes - 1);
      ranges.add((start, end));
      start = end + 1;
    }
    return ranges;
  }

  Future<int?> _probeRangeTotalBytes(
    String url,
    Map<String, dynamic> headers,
    CancelToken cancelToken,
  ) async {
    try {
      final probeHeaders = Map<String, dynamic>.from(headers)
        ..['Range'] = 'bytes=0-0';
      final response = await _httpClient.dio.get<List<int>>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 15),
          headers: probeHeaders,
        ),
      );
      if (response.statusCode == 206) {
        final contentRange = response.headers.value('content-range');
        return parseTotalBytesFromContentRange(contentRange);
      }
    } catch (_) {
      // Probe failed; caller will fall back to single-connection download.
    }
    return null;
  }

  Future<void> _downloadDirectMp4(
    DownloadTask task,
    String directUrl,
    CancelToken cancelToken,
  ) async {
    final baseName = generateVideoFilename(
      cartoonTitle: task.cartoonTitle,
      seasonTitle: task.episode.seasonTitle,
      episodeTitle: task.episode.title,
    );
    final mp4Path =
        '$_downloadDirectoryPath${Platform.pathSeparator}$baseName.mp4';
    final referer = _determineSegmentReferer(task.source, directUrl);
    final headers = <String, dynamic>{
      'User-Agent': AppHttpClient.chromeUserAgent,
    };
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }

    final totalBytes = _maxWorkers > 1
        ? await _probeRangeTotalBytes(directUrl, headers, cancelToken)
        : null;

    if (task.isCancelled || cancelToken.isCancelled) {
      if (task.isCancelled) task.setFailed('已取消下载');
      return;
    }
    if (task.phase == DownloadPhase.paused) return;

    if (totalBytes != null && totalBytes > 1024 * 1024 && _maxWorkers > 1) {
      final ok = await _downloadDirectMp4MultiRange(
        task: task,
        directUrl: directUrl,
        mp4Path: mp4Path,
        totalBytes: totalBytes,
        headers: headers,
        cancelToken: cancelToken,
      );
      if (ok ||
          task.isCancelled ||
          cancelToken.isCancelled ||
          task.phase == DownloadPhase.paused) {
        return;
      }
    }

    // Fallback when server does not support HTTP Range requests.
    var lastBytes = 0;
    task.setDownloading(completed: 0, total: 100);
    task.incrementActiveConnections();
    try {
      await _httpClient.dio.download(
        directUrl,
        mp4Path,
        cancelToken: cancelToken,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          final delta = received - lastBytes;
          if (delta > 0) {
            _bytesDownloadedThisSecond += delta;
            task.bytesDownloadedThisSecond += delta;
            lastBytes = received;
          }
          if (total > 0) {
            final percent = ((received / total) * 100).round().clamp(0, 100);
            task.setDownloading(completed: percent, total: 100);
          }
        },
      );
    } finally {
      task.decrementActiveConnections();
    }

    if (task.isCancelled) {
      task.setFailed('已取消下载');
      return;
    }
    if (task.phase == DownloadPhase.paused) return;

    task.setCompleted(mp4Path);
  }

  Future<bool> _downloadDirectMp4MultiRange({
    required DownloadTask task,
    required String directUrl,
    required String mp4Path,
    required int totalBytes,
    required Map<String, dynamic> headers,
    required CancelToken cancelToken,
  }) async {
    final ranges = buildByteRanges(totalBytes, _maxWorkers);
    if (ranges.length <= 1) return false;

    final tempDir = Directory(_taskTempDirPath(task.id));
    if (!tempDir.existsSync()) {
      tempDir.createSync(recursive: true);
    }

    final states = List<SegmentState>.generate(ranges.length, (i) {
      final chunkFile =
          File('${tempDir.path}${Platform.pathSeparator}part_$i.bin');
      final expectedLen = ranges[i].$2 - ranges[i].$1 + 1;
      if (chunkFile.existsSync() && chunkFile.lengthSync() == expectedLen) {
        return SegmentState.downloaded;
      }
      return SegmentState.pending;
    });

    task.setSegmentsStatus(states);
    final initialDone =
        states.where((s) => s == SegmentState.downloaded).length;
    task.setDownloading(completed: initialDone, total: ranges.length);

    final pendingIndices = <int>[
      for (var i = 0; i < states.length; i++)
        if (states[i] != SegmentState.downloaded) i,
    ];

    await _runConcurrentPool<int>(
      task: task,
      items: pendingIndices,
      cancelToken: cancelToken,
      onItem: (chunkIdx) async {
        final (start, end) = ranges[chunkIdx];
        final destFile =
            File('${tempDir.path}${Platform.pathSeparator}part_$chunkIdx.bin');
        final ok = await _downloadRangeChunk(
          task: task,
          url: directUrl,
          start: start,
          end: end,
          destination: destFile,
          headers: headers,
          cancelToken: cancelToken,
        );
        if (task.isCancelled ||
            cancelToken.isCancelled ||
            task.phase == DownloadPhase.paused) {
          return;
        }
        task.updateSegmentState(
          chunkIdx,
          ok ? SegmentState.downloaded : SegmentState.failed,
        );
      },
    );

    if (task.isCancelled) {
      task.setFailed('已取消下载');
      return false;
    }
    if (task.phase == DownloadPhase.paused || cancelToken.isCancelled) {
      return false;
    }

    final failedCount =
        task.segmentsStatus.where((s) => s != SegmentState.downloaded).length;
    if (failedCount > 0) {
      task.setFailed('有 $failedCount 个分片下载失败，请点击重试');
      return true;
    }

    task.setMerging(completed: 0, total: ranges.length);
    final outFile = File(mp4Path);
    if (!outFile.parent.existsSync()) {
      outFile.parent.createSync(recursive: true);
    }
    final sink = outFile.openWrite();
    try {
      for (var i = 0; i < ranges.length; i++) {
        if (task.isCancelled) {
          await sink.close();
          task.setFailed('已取消下载');
          return true;
        }
        final chunkFile =
            File('${tempDir.path}${Platform.pathSeparator}part_$i.bin');
        await sink.addStream(chunkFile.openRead());
        if (i % 4 == 0 || i == ranges.length - 1) {
          task.setMerging(completed: i + 1, total: ranges.length);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    task.setCompleted(mp4Path);
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    return true;
  }

  Future<bool> _downloadRangeChunk({
    required DownloadTask task,
    required String url,
    required int start,
    required int end,
    required File destination,
    required Map<String, dynamic> headers,
    required CancelToken cancelToken,
  }) async {
    final expectedLen = end - start + 1;
    final rangeHeaders = Map<String, dynamic>.from(headers)
      ..['Range'] = 'bytes=$start-$end';

    for (var attempt = 0; attempt < 3; attempt++) {
      if (cancelToken.isCancelled) return false;
      IOSink? sink;
      try {
        final response = await _httpClient.dio.get<ResponseBody>(
          url,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 25),
            headers: rangeHeaders,
          ),
        );
        if (response.statusCode == 206 && response.data != null) {
          final fileSink = destination.openWrite();
          sink = fileSink;
          var received = 0;
          await for (final chunk in response.data!.stream) {
            if (cancelToken.isCancelled) {
              await fileSink.close();
              sink = null;
              return false;
            }
            fileSink.add(chunk);
            received += chunk.length;
            _bytesDownloadedThisSecond += chunk.length;
            task.bytesDownloadedThisSecond += chunk.length;
          }
          await fileSink.flush();
          await fileSink.close();
          sink = null;
          if (received == expectedLen) {
            return true;
          }
        }
      } catch (_) {
        // Retry on transient error.
      } finally {
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {}
        }
      }
      if (attempt < 2 && !cancelToken.isCancelled) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return false;
  }

  Future<void> _runConcurrentPool<T>({
    required DownloadTask task,
    required List<T> items,
    required CancelToken cancelToken,
    required Future<void> Function(T item) onItem,
  }) async {
    if (items.isEmpty) return;
    var cursor = 0;
    final workerCount = min(_maxWorkers, items.length);

    Future<void> worker() async {
      while (true) {
        if (task.isCancelled ||
            cancelToken.isCancelled ||
            task.phase == DownloadPhase.paused) {
          return;
        }
        if (cursor >= items.length) return;
        final item = items[cursor++];
        task.incrementActiveConnections();
        try {
          await onItem(item);
        } finally {
          task.decrementActiveConnections();
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }

  Future<void> _downloadSegmentsConcurrently({
    required DownloadTask task,
    required List<Uri> segmentUrls,
    required List<int> indices,
    required Directory tempDir,
    required String? referer,
    required CancelToken cancelToken,
  }) async {
    await _runConcurrentPool<int>(
      task: task,
      items: indices,
      cancelToken: cancelToken,
      onItem: (segIdx) async {
        final ok = await _downloadSingleSegment(
          task: task,
          url: segmentUrls[segIdx],
          destination:
              File('${tempDir.path}${Platform.pathSeparator}chunk_$segIdx.ts'),
          referer: referer,
          cancelToken: cancelToken,
        );
        if (task.isCancelled ||
            cancelToken.isCancelled ||
            task.phase == DownloadPhase.paused) {
          return;
        }
        task.updateSegmentState(
          segIdx,
          ok ? SegmentState.downloaded : SegmentState.failed,
        );
      },
    );
  }

  Future<bool> _downloadSingleSegment({
    required DownloadTask task,
    required Uri url,
    required File destination,
    required String? referer,
    required CancelToken cancelToken,
  }) async {
    final candidateReferers = <String>[
      if (referer != null && referer.isNotEmpty) referer,
      '',
      if (url.host.isNotEmpty) 'https://${url.host}/',
    ];

    for (var attempt = 0; attempt < 3; attempt++) {
      if (cancelToken.isCancelled) return false;
      final ref = candidateReferers[attempt % candidateReferers.length];
      final headers = <String, dynamic>{
        'User-Agent': AppHttpClient.chromeUserAgent,
      };
      if (ref.isNotEmpty) {
        headers['Referer'] = ref;
      }

      var lastReceived = 0;
      try {
        final response = await _httpClient.dio.get<List<int>>(
          url.toString(),
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 15),
            headers: headers,
          ),
          onReceiveProgress: (received, _) {
            final delta = received - lastReceived;
            if (delta > 0) {
              _bytesDownloadedThisSecond += delta;
              task.bytesDownloadedThisSecond += delta;
              lastReceived = received;
            }
          },
        );
        final data = response.data;
        if (response.statusCode == 200 && data != null && data.isNotEmpty) {
          await destination.writeAsBytes(data, flush: false);
          if (data.length > lastReceived) {
            final remaining = data.length - lastReceived;
            _bytesDownloadedThisSecond += remaining;
            task.bytesDownloadedThisSecond += remaining;
          }
          return true;
        }
        if (response.statusCode == 403 ||
            response.statusCode == 429 ||
            response.statusCode == 503) {
          await Future<void>.delayed(Duration(seconds: 1 + attempt));
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) return false;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    return false;
  }

  void _updateSpeed() {
    final totalBytes = _bytesDownloadedThisSecond;
    _bytesDownloadedThisSecond = 0;
    currentDownloadSpeed = totalBytes.toDouble();
    for (final task in downloadTasks) {
      final taskBytes = task.bytesDownloadedThisSecond;
      task.bytesDownloadedThisSecond = 0;
      if (task.phase == DownloadPhase.downloading) {
        task.updateDownloadSpeed(formatSpeed(taskBytes.toDouble()));
      }
    }
    notifyListeners();
  }

  bool _isDirectMediaHref(String href) {
    return (href.startsWith('http://') || href.startsWith('https://')) &&
        (href.contains('.m3u8') ||
            href.contains('.mp4') ||
            href.contains('/m3u8/'));
  }

  bool _isHlsUrl(String url) {
    return url.contains('.m3u8') ||
        url.contains('playlist.m3u8') ||
        url.contains('/m3u8/');
  }

  String? _determineSegmentReferer(SearchSource source, String targetUrlStr) {
    if (source == SearchSource.acgbibi ||
        targetUrlStr.contains('v2player') ||
        targetUrlStr.contains('akamaized') ||
        targetUrlStr.contains('tiktokcdn')) {
      return 'https://art.v2player.top:8989/';
    }
    final uri = Uri.tryParse(targetUrlStr);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    if (host.contains(source.domain)) {
      return '${source.baseUrl}/';
    }
    return null;
  }

  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
    } else if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
  }

  static String cleanTitleResolution(String title) {
    var cleaned = title;
    for (final source in SearchSource.values) {
      cleaned = cleaned
          .replaceAll(' - ${source.displayName}', '')
          .replaceAll('【${source.displayName}】', '')
          .replaceAll('[${source.displayName}]', '')
          .replaceAll('(${source.displayName})', '');
    }
    cleaned = cleaned.replaceAll(
      RegExp(r'(4[kK]|2[kK]|1080[pP]|720[pP])版?'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[\（\【]\s*[\)\]\）\】]'), '');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String generateVideoFilename({
    required String cartoonTitle,
    required String seasonTitle,
    required String episodeTitle,
    String resolutionLabel = '',
  }) {
    final cleanedTitle = cleanTitleResolution(cartoonTitle);
    final season = seasonTitle.trim();
    final isSource = season.contains('源') ||
        season.contains('播放') ||
        season.contains('精品') ||
        SearchSource.values.any(
          (s) => season.contains(s.displayName) || season.contains(s.domain),
        ) ||
        season.toLowerCase().contains('acgbibi') ||
        season.toLowerCase().contains('4kvms');

    final String rawFilename;
    if (season.isEmpty || isSource) {
      rawFilename = '$cleanedTitle - $episodeTitle$resolutionLabel';
    } else {
      final cleanSeason = season.split('【').first.trim();
      rawFilename =
          '$cleanedTitle - $cleanSeason $episodeTitle$resolutionLabel';
    }
    return sanitizeFilename(rawFilename);
  }

  static String sanitizeFilename(String filename) {
    return filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), '').trim();
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _persistDebounceTimer?.cancel();
    for (final token in _activeCancelTokens.values) {
      token.cancel('disposed');
    }
    _activeCancelTokens.clear();
    super.dispose();
  }
}
