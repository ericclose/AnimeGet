import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/anime_models.dart';
import '../services/download_manager.dart';
import 'widgets/common_widgets.dart';

enum _TaskFilter {
  all('全部'),
  active('进行中'),
  completed('已完成'),
  attention('暂停/异常');

  const _TaskFilter(this.label);
  final String label;
}

class TasksPane extends StatefulWidget {
  const TasksPane({
    super.key,
    required this.manager,
    required this.isDesktop,
    this.showMobileDetail = false,
    this.onMobileDetailChanged,
  });

  final DownloadManager manager;
  final bool isDesktop;
  final bool showMobileDetail;
  final ValueChanged<bool>? onMobileDetailChanged;

  @override
  State<TasksPane> createState() => _TasksPaneState();
}

class _TasksPaneState extends State<TasksPane> {
  String? _selectedTaskId;
  bool _localShowMobileDetail = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = <String>{};
  _TaskFilter _filter = _TaskFilter.all;

  bool get _isShowingMobileDetail => widget.onMobileDetailChanged != null
      ? widget.showMobileDetail
      : _localShowMobileDetail;

  void _setMobileDetail(bool show) {
    if (widget.onMobileDetailChanged != null) {
      widget.onMobileDetailChanged!(show);
    } else {
      setState(() => _localShowMobileDetail = show);
    }
  }

  List<DownloadTask> _filteredTasks(List<DownloadTask> all) {
    switch (_filter) {
      case _TaskFilter.all:
        return all;
      case _TaskFilter.active:
        return all
            .where((t) => t.isActive || t.phase == DownloadPhase.queued)
            .toList();
      case _TaskFilter.completed:
        return all.where((t) => t.phase == DownloadPhase.completed).toList();
      case _TaskFilter.attention:
        return all
            .where(
              (t) =>
                  t.phase == DownloadPhase.paused ||
                  t.phase == DownloadPhase.failed,
            )
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allTasks = widget.manager.downloadTasks;
    final tasks = _filteredTasks(allTasks);
    final selectedTask =
        tasks.where((t) => t.id == _selectedTaskId).firstOrNull ??
            (tasks.isNotEmpty ? tasks.first : null);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1360),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.isDesktop ? 24 : 14,
            widget.isDesktop ? 20 : 12,
            widget.isDesktop ? 24 : 14,
            widget.isDesktop ? 20 : 12,
          ),
          child: widget.isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: 380,
                      child: _buildTaskList(
                        context,
                        allTasks,
                        tasks,
                        selectedTask,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTaskDetail(context, selectedTask)),
                  ],
                )
              : (_isShowingMobileDetail && selectedTask != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: () => _setMobileDetail(false),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('返回任务列表'),
                        ),
                        Expanded(child: _buildTaskDetail(context, selectedTask)),
                      ],
                    )
                  : _buildTaskList(context, allTasks, tasks, selectedTask)),
        ),
      ),
    );
  }

  Widget _buildTaskList(
    BuildContext context,
    List<DownloadTask> allTasks,
    List<DownloadTask> tasks,
    DownloadTask? selectedTask,
  ) {
    final cs = Theme.of(context).colorScheme;
    final manager = widget.manager;
    final hasActive = allTasks.any(
      (t) => t.isActive || t.phase == DownloadPhase.queued,
    );
    final hasCompleted = allTasks.any(
      (t) => t.phase == DownloadPhase.completed,
    );

    int countForFilter(_TaskFilter f) {
      return switch (f) {
        _TaskFilter.all => allTasks.length,
        _TaskFilter.active => allTasks
            .where((t) => t.isActive || t.phase == DownloadPhase.queued)
            .length,
        _TaskFilter.completed =>
          allTasks.where((t) => t.phase == DownloadPhase.completed).length,
        _TaskFilter.attention => allTasks
            .where(
              (t) =>
                  t.phase == DownloadPhase.paused ||
                  t.phase == DownloadPhase.failed,
            )
            .length,
      };
    }

    final listContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.isDesktop ? 16 : 4,
            widget.isDesktop ? 14 : 4,
            widget.isDesktop ? 10 : 0,
            8,
          ),
          child: _isSelectionMode
              ? Row(
                  children: <Widget>[
                    Text(
                      '已选 ${_selectedIds.length} 项',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          final visibleIds = tasks.map((t) => t.id).toSet();
                          final allSelected =
                              visibleIds.isNotEmpty &&
                              visibleIds.every(_selectedIds.contains);
                          if (allSelected) {
                            _selectedIds.removeAll(visibleIds);
                          } else {
                            _selectedIds.addAll(visibleIds);
                          }
                        });
                      },
                      child: Text(
                        tasks.isNotEmpty &&
                                tasks.every((t) => _selectedIds.contains(t.id))
                            ? '取消全选'
                            : '全选',
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: cs.error,
                      ),
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () {
                              final selectedTasks = allTasks
                                  .where((t) => _selectedIds.contains(t.id))
                                  .toList();
                              _confirmDeleteTasks(context, selectedTasks);
                            },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text('删除 (${_selectedIds.length})'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _isSelectionMode = false;
                        _selectedIds.clear();
                      }),
                      child: const Text('完成'),
                    ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    Text(
                      '下载队列 (${allTasks.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (allTasks.isNotEmpty)
                      IconButton(
                        tooltip: '多选删除',
                        icon: const Icon(Icons.checklist_rounded, size: 20),
                        onPressed: () => setState(() {
                          _isSelectionMode = true;
                          _selectedIds.clear();
                        }),
                      ),
                    if (hasActive)
                      IconButton(
                        tooltip: '全部暂停',
                        icon: const Icon(Icons.pause_circle_outline, size: 20),
                        onPressed: manager.pauseAllTasks,
                      ),
                    if (allTasks.any((t) => t.phase == DownloadPhase.paused))
                      IconButton(
                        tooltip: '全部继续',
                        icon: const Icon(Icons.play_circle_outline, size: 20),
                        onPressed: manager.resumeAllTasks,
                      ),
                    if (hasCompleted)
                      IconButton(
                        tooltip: '清除已完成',
                        icon: const Icon(
                          Icons.cleaning_services_outlined,
                          size: 19,
                        ),
                        onPressed: () => _confirmClearCompleted(context),
                      ),
                  ],
                ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(
            widget.isDesktop ? 16 : 2,
            0,
            widget.isDesktop ? 16 : 2,
            10,
          ),
          child: Row(
            children: _TaskFilter.values.map((f) {
              final count = countForFilter(f);
              final labelText = count > 0 ? '${f.label} $count' : f.label;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(
                    labelText,
                    style: TextStyle(fontSize: widget.isDesktop ? 13 : 12),
                  ),
                  labelPadding: EdgeInsets.symmetric(
                    horizontal: widget.isDesktop ? 6 : 2,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isDesktop ? 8 : 4,
                  ),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),
        if (widget.isDesktop) Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.download_for_offline_outlined,
                          size: 30,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        allTasks.isEmpty ? '暂无下载任务' : '当前筛选下无任务',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.all(widget.isDesktop ? 12 : 0),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return ListenableBuilder(
                      listenable: task,
                      builder: (context, _) {
                        final isChecked =
                            _isSelectionMode && _selectedIds.contains(task.id);
                        final isSelected = isChecked ||
                            (!_isSelectionMode &&
                                widget.isDesktop &&
                                selectedTask?.id == task.id);
                        final progressColor = switch (task.phase) {
                          DownloadPhase.completed => const Color(0xFF047857),
                          DownloadPhase.failed => cs.error,
                          DownloadPhase.paused => cs.outline,
                          _ => cs.primary,
                        };
                        return Material(
                          color: isSelected
                              ? cs.primaryContainer.withValues(alpha: 0.45)
                              : cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onLongPress: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _isSelectionMode = true;
                                _selectedIds.add(task.id);
                              });
                            },
                            onTap: () {
                              if (_isSelectionMode) {
                                setState(() {
                                  if (_selectedIds.contains(task.id)) {
                                    _selectedIds.remove(task.id);
                                  } else {
                                    _selectedIds.add(task.id);
                                  }
                                });
                                return;
                              }
                              setState(() {
                                _selectedTaskId = task.id;
                              });
                              if (!widget.isDesktop) {
                                _setMobileDetail(true);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? cs.primary
                                      : cs.outlineVariant.withValues(alpha: 0.7),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          '${task.cartoonTitle} - ${task.episodeTitle}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (task.activeConnections > 0) ...<Widget>[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.secondaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Icon(
                                                Icons.hub_outlined,
                                                size: 11,
                                                color: cs.onSecondaryContainer,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                '${task.activeConnections}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontFamily: 'monospace',
                                                  color: cs.onSecondaryContainer,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (task.downloadSpeed.isNotEmpty) ...<Widget>[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.primaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            task.downloadSpeed,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                              color: cs.onPrimaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: task.progress,
                                    minHeight: 5,
                                    color: progressColor,
                                    backgroundColor: cs.surfaceContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          task.statusDescription,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: task.phase ==
                                                    DownloadPhase.failed
                                                ? cs.error
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      _taskActionButtons(context, task),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );

    if (!widget.isDesktop) {
      return listContent;
    }

    return DashboardSurfaceCard(child: listContent);
  }

  Widget _taskActionButtons(BuildContext context, DownloadTask task) {
    final manager = widget.manager;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (task.phase == DownloadPhase.downloading ||
            task.phase == DownloadPhase.parsing)
          IconButton(
            icon: const Icon(Icons.pause, size: 18),
            tooltip: '暂停',
            visualDensity: VisualDensity.compact,
            onPressed: () => manager.pauseTask(task),
          ),
        if (task.phase == DownloadPhase.paused)
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 18),
            tooltip: '继续',
            visualDensity: VisualDensity.compact,
            onPressed: () => manager.resumeTask(task),
          ),
        if (task.phase == DownloadPhase.failed)
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '重试',
            visualDensity: VisualDensity.compact,
            onPressed: () => manager.retryTask(task),
          ),
        if (task.phase == DownloadPhase.completed) ...<Widget>[
          IconButton(
            icon: const Icon(Icons.play_circle_outline, size: 19),
            tooltip: '播放视频',
            visualDensity: VisualDensity.compact,
            onPressed: () => manager.openVideoFile(task.outputPath),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 18),
            tooltip: '打开所在目录',
            visualDensity: VisualDensity.compact,
            onPressed: () => manager.openInFileManager(task.outputPath),
          ),
        ],
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: '删除',
          visualDensity: VisualDensity.compact,
          onPressed: () => _confirmDeleteTask(context, task),
        ),
      ],
    );
  }

  Widget _buildTaskDetail(BuildContext context, DownloadTask? task) {
    final cs = Theme.of(context).colorScheme;
    if (task == null) {
      return DashboardSurfaceCard(
        child: Center(
          child: Text(
            '请选择左侧任务查看分片与进度详情',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: task,
      builder: (context, _) {
        return DashboardSurfaceCard(
          padding: EdgeInsets.all(widget.isDesktop ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${task.cartoonTitle} — ${task.episodeTitle}',
                style: (widget.isDesktop
                        ? Theme.of(context).textTheme.headlineSmall
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _buildTaskMetaBadges(context, task),
              const SizedBox(height: 12),
              _buildTaskStatusRow(context, task),
              if (task.phase == DownloadPhase.completed) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () =>
                          widget.manager.openVideoFile(task.outputPath),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('播放视频'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          widget.manager.openInFileManager(task.outputPath),
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('打开所在目录'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: task.progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (task.resolvedUrl != null) ...<Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              '直链地址',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: task.resolvedUrl!),
                                );
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text('已复制直链地址'),
                                      duration: Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              label: const Text(
                                '复制',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: SelectableText(
                            task.resolvedUrl!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (task.segmentsStatus.isNotEmpty) ...<Widget>[
                        Text(
                          '分片状态网格 (${task.completedCount}/${task.totalCount})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: task.segmentsStatus.map((state) {
                            final Color color;
                            switch (state) {
                              case SegmentState.downloaded:
                                color = const Color(0xFF047857);
                              case SegmentState.failed:
                                color = cs.error;
                              case SegmentState.pending:
                                color = cs.surfaceContainer;
                            }
                            return Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaskMetaBadges(BuildContext context, DownloadTask task) {
    final cs = Theme.of(context).colorScheme;
    final (IconData phaseIcon, String phaseLabel, Color bg, Color fg) =
        switch (task.phase) {
      DownloadPhase.completed => (
          Icons.check_circle_outline,
          '下载成功',
          const Color(0xFF047857).withValues(alpha: 0.14),
          const Color(0xFF047857),
        ),
      DownloadPhase.failed => (
          Icons.error_outline,
          '下载失败',
          cs.errorContainer,
          cs.onErrorContainer,
        ),
      DownloadPhase.paused => (
          Icons.pause_circle_outline,
          '已暂停',
          cs.surfaceContainer,
          cs.onSurfaceVariant,
        ),
      DownloadPhase.downloading => (
          Icons.downloading,
          '下载中',
          cs.primaryContainer,
          cs.onPrimaryContainer,
        ),
      DownloadPhase.merging || DownloadPhase.remuxing => (
          Icons.movie_creation_outlined,
          task.phase == DownloadPhase.merging ? '合并中' : '转码中',
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
        ),
      DownloadPhase.parsing => (
          Icons.manage_search,
          '解析中',
          cs.secondaryContainer,
          cs.onSecondaryContainer,
        ),
      DownloadPhase.queued => (
          Icons.schedule,
          '等待中',
          cs.surfaceContainer,
          cs.onSurfaceVariant,
        ),
    };

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        _iconPill(
          icon: Icons.dns_outlined,
          label: task.source.displayName,
          backgroundColor: cs.surfaceContainerLow,
          foregroundColor: cs.onSurfaceVariant,
          borderColor: cs.outlineVariant,
        ),
        _iconPill(
          icon: phaseIcon,
          label: phaseLabel,
          backgroundColor: bg,
          foregroundColor: fg,
        ),
        if (task.isActive || task.activeConnections > 0)
          _iconPill(
            icon: Icons.hub_outlined,
            label: '${task.activeConnections}',
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
          ),
        if (task.downloadSpeed.isNotEmpty)
          _iconPill(
            icon: Icons.speed,
            label: task.downloadSpeed,
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
          ),
      ],
    );
  }

  Future<void> _confirmDeleteTask(
    BuildContext context,
    DownloadTask task,
  ) {
    return _confirmDeleteTasks(context, <DownloadTask>[task]);
  }

  Future<void> _confirmDeleteTasks(
    BuildContext context,
    List<DownloadTask> tasks,
  ) async {
    if (tasks.isEmpty) return;
    final hasLocalFile = tasks.any(
      (t) =>
          t.outputPath != null &&
          t.outputPath!.isNotEmpty &&
          File(t.outputPath!).existsSync(),
    );
    var deleteLocalFile = false;
    final message = tasks.length == 1
        ? '确定要删除「${tasks.first.cartoonTitle} - ${tasks.first.episodeTitle}」吗？'
        : '确定要删除选中的 ${tasks.length} 个任务吗？';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('确认删除任务'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(message),
                  if (hasLocalFile) ...<Widget>[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('同时删除本地视频文件'),
                      value: deleteLocalFile,
                      onChanged: (val) => setDialogState(
                        () => deleteLocalFile = val ?? false,
                      ),
                    ),
                  ],
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      widget.manager.deleteTasks(tasks, deleteFile: deleteLocalFile);
      if (mounted) {
        setState(() {
          for (final t in tasks) {
            _selectedIds.remove(t.id);
          }
          if (_selectedIds.isEmpty) {
            _isSelectionMode = false;
          }
        });
      }
    }
  }

  Future<void> _confirmClearCompleted(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除已完成任务'),
        content: const Text('确定要清除所有已完成的任务记录吗？（不会删除本地视频文件）'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.manager.clearCompletedTasks();
    }
  }

  Widget _iconPill({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskStatusRow(BuildContext context, DownloadTask task) {
    final cs = Theme.of(context).colorScheme;
    if (task.phase == DownloadPhase.completed &&
        task.outputPath != null &&
        task.outputPath!.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.folder_outlined,
                size: 16,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                task.outputPath!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isError = task.phase == DownloadPhase.failed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: isError ? cs.error : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            task.statusDescription,
            style: TextStyle(
              fontSize: 13,
              color: isError ? cs.error : cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
