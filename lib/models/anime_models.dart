import 'package:flutter/foundation.dart';

enum SearchSource {
  kvms4(
    displayName: '4K影视',
    domain: 'www.4kvms.com',
    apiBaseUrl: 'https://www.4kvms.com',
  ),
  acgbibi(
    displayName: 'acgbibi【精品】',
    domain: 'www.acgbibi.com',
    apiBaseUrl: 'https://www.acgbibi.com',
  );

  const SearchSource({
    required this.displayName,
    required this.domain,
    required this.apiBaseUrl,
  });

  final String displayName;
  final String domain;
  final String apiBaseUrl;

  String get baseUrl => 'https://$domain';

  static SearchSource fromName(String? name) {
    return SearchSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => SearchSource.kvms4,
    );
  }
}

class Cartoon {
  Cartoon({
    required this.id,
    required this.title,
    required this.link,
    this.source = SearchSource.kvms4,
  });

  final String id;
  final String title;
  final String link;
  final SearchSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cartoon && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Episode {
  Episode({
    required this.id,
    required this.epNum,
    required this.title,
    required this.href,
    this.seasonTitle = '',
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id']?.toString() ?? '',
      epNum: (json['epNum'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? '',
      href: json['href']?.toString() ?? '',
      seasonTitle: json['seasonTitle']?.toString() ?? '',
    );
  }

  final String id;
  final int epNum;
  final String title;
  final String href;
  final String seasonTitle;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'epNum': epNum,
        'title': title,
        'href': href,
        'seasonTitle': seasonTitle,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Episode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ResolutionOption {
  const ResolutionOption({
    required this.width,
    required this.height,
    required this.label,
    required this.url,
  });

  final int width;
  final int height;
  final String label;
  final String url;
}

enum SegmentState {
  pending,
  downloaded,
  failed,
}

enum DownloadPhase {
  queued,
  parsing,
  downloading,
  paused,
  merging,
  remuxing,
  completed,
  failed,
}

class DownloadTask extends ChangeNotifier {
  DownloadTask({
    required this.id,
    required this.cartoonTitle,
    required this.episodeNum,
    required this.episodeTitle,
    required this.episode,
    this.source = SearchSource.kvms4,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final task = DownloadTask(
      id: json['id']?.toString() ?? '',
      cartoonTitle: json['cartoonTitle']?.toString() ?? '',
      episodeNum: (json['episodeNum'] as num?)?.toInt() ?? 1,
      episodeTitle: json['episodeTitle']?.toString() ?? '',
      episode: Episode.fromJson(
        (json['episode'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
      source: SearchSource.fromName(json['source']?.toString()),
    );

    final rawPhase = json['phase']?.toString() ?? 'queued';
    var restoredPhase = DownloadPhase.values.firstWhere(
      (p) => p.name == rawPhase,
      orElse: () => DownloadPhase.queued,
    );
    // Any in-flight task from a previous session becomes paused on restart.
    if (restoredPhase == DownloadPhase.parsing ||
        restoredPhase == DownloadPhase.downloading ||
        restoredPhase == DownloadPhase.merging ||
        restoredPhase == DownloadPhase.remuxing) {
      restoredPhase = DownloadPhase.paused;
    }

    task._phase = restoredPhase;
    task._completedCount = (json['completedCount'] as num?)?.toInt() ?? 0;
    task._totalCount = (json['totalCount'] as num?)?.toInt() ?? 0;
    task.resolvedUrl = json['resolvedUrl']?.toString();
    task.playlistUrl = json['playlistUrl']?.toString();
    task._outputPath = json['outputPath']?.toString();
    task._errorReason = json['errorReason']?.toString();
    task.isCancelled = (json['isCancelled'] as bool?) ?? false;

    final segList = json['segmentsStatus'];
    if (segList is List) {
      task._segmentsStatus = segList
          .map(
            (e) => SegmentState.values[
                ((e as num?)?.toInt() ?? 0).clamp(0, SegmentState.values.length - 1)],
          )
          .toList();
    }
    return task;
  }

  final String id;
  final String cartoonTitle;
  final int episodeNum;
  final String episodeTitle;
  final Episode episode;
  final SearchSource source;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'cartoonTitle': cartoonTitle,
        'episodeNum': episodeNum,
        'episodeTitle': episodeTitle,
        'episode': episode.toJson(),
        'source': source.name,
        'phase': _phase.name,
        'completedCount': _completedCount,
        'totalCount': _totalCount,
        'segmentsStatus': _segmentsStatus.map((s) => s.index).toList(),
        'resolvedUrl': resolvedUrl,
        'playlistUrl': playlistUrl,
        'outputPath': _outputPath,
        'errorReason': _errorReason,
        'isCancelled': isCancelled,
      };

  DownloadPhase _phase = DownloadPhase.queued;
  DownloadPhase get phase => _phase;

  int _completedCount = 0;
  int get completedCount => _completedCount;

  int _totalCount = 0;
  int get totalCount => _totalCount;

  String _downloadSpeed = '';
  String get downloadSpeed => _downloadSpeed;

  int _activeConnections = 0;
  int get activeConnections => _activeConnections;

  int bytesDownloadedThisSecond = 0;

  List<SegmentState> _segmentsStatus = <SegmentState>[];
  List<SegmentState> get segmentsStatus => _segmentsStatus;

  String? resolvedUrl;
  String? playlistUrl;

  String _parsingStage = '正在解析直链...';
  String get parsingStage => _parsingStage;

  String? _outputPath;
  String? get outputPath => _outputPath;

  String? _errorReason;
  String? get errorReason => _errorReason;

  bool isCancelled = false;

  bool get isActive =>
      !isCancelled &&
      (_phase == DownloadPhase.parsing ||
          _phase == DownloadPhase.downloading ||
          _phase == DownloadPhase.merging ||
          _phase == DownloadPhase.remuxing);

  double get progress {
    switch (_phase) {
      case DownloadPhase.downloading:
      case DownloadPhase.paused:
        return _totalCount > 0 ? (_completedCount / _totalCount) * 0.9 : 0.0;
      case DownloadPhase.merging:
        return _totalCount > 0
            ? 0.9 + 0.08 * (_completedCount / _totalCount)
            : 0.9;
      case DownloadPhase.remuxing:
        return 0.98;
      case DownloadPhase.completed:
        return 1.0;
      case DownloadPhase.queued:
      case DownloadPhase.parsing:
      case DownloadPhase.failed:
        return 0.0;
    }
  }

  String get statusDescription {
    switch (_phase) {
      case DownloadPhase.queued:
        return '等待中';
      case DownloadPhase.parsing:
        return _parsingStage;
      case DownloadPhase.downloading:
        final percent = _totalCount > 0 ? (_completedCount / _totalCount) * 100 : 0.0;
        return '正在下载分片: $_completedCount/$_totalCount (${percent.toStringAsFixed(1)}%)';
      case DownloadPhase.paused:
        return '已暂停 ($_completedCount/$_totalCount)';
      case DownloadPhase.merging:
        final percent = _totalCount > 0 ? (_completedCount / _totalCount) * 100 : 0.0;
        return '正在合并分片: $_completedCount/$_totalCount (${percent.toStringAsFixed(1)}%)';
      case DownloadPhase.remuxing:
        return '正在转换为 MP4...';
      case DownloadPhase.completed:
        return '下载成功！保存至: ${_outputPath ?? ""}';
      case DownloadPhase.failed:
        return '失败: ${_errorReason ?? "未知错误"}';
    }
  }

  void setQueued() {
    isCancelled = false;
    _phase = DownloadPhase.queued;
    _errorReason = null;
    notifyListeners();
  }

  void setParsing([String stage = '正在解析直链...']) {
    _phase = DownloadPhase.parsing;
    _parsingStage = stage;
    notifyListeners();
  }

  void setDownloading({required int completed, required int total}) {
    _phase = DownloadPhase.downloading;
    _completedCount = completed;
    _totalCount = total;
    notifyListeners();
  }

  void setPaused() {
    _phase = DownloadPhase.paused;
    _downloadSpeed = '';
    _activeConnections = 0;
    notifyListeners();
  }

  void setMerging({required int completed, required int total}) {
    _phase = DownloadPhase.merging;
    _completedCount = completed;
    _totalCount = total;
    _activeConnections = 0;
    notifyListeners();
  }

  void setRemuxing() {
    _phase = DownloadPhase.remuxing;
    _activeConnections = 0;
    notifyListeners();
  }

  void setCompleted(String path) {
    _phase = DownloadPhase.completed;
    _outputPath = path;
    _downloadSpeed = '';
    _activeConnections = 0;
    notifyListeners();
  }

  void setFailed(String reason) {
    _phase = DownloadPhase.failed;
    _errorReason = reason;
    _downloadSpeed = '';
    _activeConnections = 0;
    notifyListeners();
  }

  void incrementActiveConnections() {
    _activeConnections++;
    notifyListeners();
  }

  void decrementActiveConnections() {
    if (_activeConnections > 0) {
      _activeConnections--;
      notifyListeners();
    }
  }

  void updateDownloadSpeed(String speed) {
    if (_downloadSpeed == speed) return;
    _downloadSpeed = speed;
    notifyListeners();
  }

  void setSegmentsStatus(List<SegmentState> states) {
    _segmentsStatus = states;
    notifyListeners();
  }

  void updateSegmentState(int index, SegmentState state) {
    if (index < 0 || index >= _segmentsStatus.length) return;
    _segmentsStatus[index] = state;
    _completedCount =
        _segmentsStatus.where((s) => s == SegmentState.downloaded).length;
    _totalCount = _segmentsStatus.length;
    notifyListeners();
  }
}
