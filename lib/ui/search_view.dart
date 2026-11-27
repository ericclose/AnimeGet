import 'package:material_ui/material_ui.dart';

import '../models/anime_models.dart';
import '../services/download_manager.dart';
import 'theme.dart';
import 'widgets/common_widgets.dart';

class SearchPane extends StatefulWidget {
  const SearchPane({
    super.key,
    required this.manager,
    required this.isDesktop,
    required this.onStartDownloadPressed,
  });

  final DownloadManager manager;
  final bool isDesktop;
  final VoidCallback onStartDownloadPressed;

  @override
  State<SearchPane> createState() => _SearchPaneState();
}

class _SearchPaneState extends State<SearchPane> {
  final TextEditingController _searchController = TextEditingController();

  String _selectedSeason = '';
  bool _multiSelectMode = true;
  Cartoon? _lastCartoon;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _syncSeason() {
    final eps = widget.manager.episodes;
    if (widget.manager.selectedCartoon != _lastCartoon) {
      _lastCartoon = widget.manager.selectedCartoon;
      _selectedSeason = eps.isNotEmpty ? eps.first.seasonTitle : '';
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncSeason();

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.isDesktop) ...<Widget>[
                _buildKpiStrip(context),
                const SizedBox(height: 16),
              ],
              if (widget.isDesktop || widget.manager.selectedCartoon == null) ...<Widget>[
                _buildToolbarPanel(context),
                SizedBox(height: widget.isDesktop ? 16 : 12),
              ],
              Expanded(
                child: widget.isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(
                            width: 340,
                            child: _buildResultsPanel(context),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDetailPanel(context)),
                        ],
                      )
                    : (widget.manager.selectedCartoon != null
                        ? Column(
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(0, 34),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed:
                                        widget.manager.clearSelectedCartoon,
                                    icon: const Icon(Icons.arrow_back, size: 18),
                                    label: const Text('返回搜索结果'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(child: _buildDetailPanel(context)),
                            ],
                          )
                        : _buildResultsPanel(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = widget.manager;
    final activeCount = manager.downloadTasks.where((t) => t.isActive).length;
    final completedCount = manager.downloadTasks
        .where((t) => t.phase == DownloadPhase.completed)
        .length;

    return Row(
      children: <Widget>[
        Expanded(
          child: _kpiCard(
            context,
            icon: Icons.dns_outlined,
            accent: cs.primary,
            value: '${SearchSource.values.length}',
            label: '可用动漫源',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _kpiCard(
            context,
            icon: Icons.downloading_outlined,
            accent: cs.tertiary,
            value: '$activeCount',
            label: '进行中任务',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _kpiCard(
            context,
            icon: Icons.check_circle_outline,
            accent: const Color(0xFF047857),
            value: '$completedCount',
            label: '已完成剧集',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _kpiCard(
            context,
            icon: Icons.speed_outlined,
            accent: cs.secondary,
            value: manager.currentDownloadSpeedString,
            label: '实时下载速率',
            isMono: true,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String value,
    required String label,
    bool isMono = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isMono ? 18 : 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: isMono ? 'monospace' : null,
                              fontFeatures: isMono
                                  ? const <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ]
                                  : null,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = widget.manager;

    return Container(
      padding: EdgeInsets.all(widget.isDesktop ? 18 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(widget.isDesktop ? 22 : 18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: widget.isDesktop ? 46 : 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: cs.outline),
                  ),
                  padding: EdgeInsets.only(
                    left: widget.isDesktop ? 16 : 12,
                    right: 5,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.search, size: 19, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: widget.isDesktop
                                ? '搜索动漫名称 (例如: 大王饶命)'
                                : '搜索动漫名称，如 大王饶命',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (val) => manager.performSearch(val),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, _) {
                          if (value.text.isEmpty || manager.isSearching) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            tooltip: '清除输入',
                            onPressed: () {
                              _searchController.clear();
                            },
                          );
                        },
                      ),
                      if (manager.isSearching)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        FilledButton(
                          onPressed: () =>
                              manager.performSearch(_searchController.text),
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: widget.isDesktop ? 16 : 12,
                            ),
                            minimumSize: const Size(0, 34),
                          ),
                          child: const Text('检索'),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.isDesktop) ...<Widget>[
                const SizedBox(width: 14),
                ...SearchSource.values.map((source) {
                  final selected = manager.selectedSource == source;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(source.displayName),
                      selected: selected,
                      onSelected: (_) {
                        manager.changeSource(source);
                        if (_searchController.text.trim().isNotEmpty) {
                          manager.performSearch(_searchController.text);
                        }
                      },
                    ),
                  );
                }),
              ],
            ],
          ),
          if (!widget.isDesktop) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: SearchSource.values.map((source) {
                return ChoiceChip(
                  label: Text(source.displayName),
                  selected: manager.selectedSource == source,
                  onSelected: (_) {
                    manager.changeSource(source);
                    if (_searchController.text.trim().isNotEmpty) {
                      manager.performSearch(_searchController.text);
                    }
                  },
                );
              }).toList(),
            ),
          ],
          if (manager.searchHistory.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Text(
                  '最近搜索:',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: manager.searchHistory.map((term) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            label: Text(term, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _searchController.text = term;
                              manager.performSearch(term);
                            },
                            onDeleted: () =>
                                manager.removeSearchHistoryItem(term),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: manager.clearSearchHistory,
                  child: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = widget.manager;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.isDesktop ? 16 : 4,
        widget.isDesktop ? 14 : 4,
        widget.isDesktop ? 16 : 4,
        widget.isDesktop ? 10 : 8,
      ),
      child: Row(
        children: <Widget>[
          Text(
            '搜索结果',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '${manager.searchResults.length} 条',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final listBody = manager.searchResults.isEmpty
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
                    Icons.video_library_outlined,
                    size: 30,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '请输入动漫关键词检索',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        : ListView.separated(
            padding: EdgeInsets.all(widget.isDesktop ? 12 : 0),
            itemCount: manager.searchResults.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final cartoon = manager.searchResults[index];
              final isSelected = manager.selectedCartoon?.id == cartoon.id;
              final badgeColor = AppTheme.colorByTitle(cartoon.title);
              final initialChar = cartoon.title.isNotEmpty
                  ? cartoon.title.characters.first
                  : '?';
              return Material(
                color: isSelected
                    ? cs.primaryContainer.withValues(alpha: 0.6)
                    : cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => manager.selectCartoon(cartoon),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? cs.primary
                            : cs.outlineVariant.withValues(alpha: 0.7),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            initialChar,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                cartoon.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? cs.onPrimaryContainer
                                      : cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cartoon.source.displayName,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color:
                              isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

    if (!widget.isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          Expanded(child: listBody),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(child: listBody),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = widget.manager;
    final cartoon = manager.selectedCartoon;

    if (cartoon == null) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.movie_filter_outlined,
                size: 52,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                '请在左侧检索并选择动漫',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final seasons = <String>[];
    for (final ep in manager.episodes) {
      if (!seasons.contains(ep.seasonTitle)) {
        seasons.add(ep.seasonTitle);
      }
    }
    final activeSeason = _selectedSeason.isEmpty
        ? (seasons.isNotEmpty ? seasons.first : '')
        : _selectedSeason;
    final seasonEps = manager.episodes
        .where((ep) => ep.seasonTitle == activeSeason)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: widget.isDesktop
                ? const EdgeInsets.fromLTRB(24, 20, 24, 14)
                : const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        cartoon.title,
                        style: (widget.isDesktop
                                ? Theme.of(context).textTheme.headlineSmall
                                : Theme.of(context).textTheme.titleLarge)
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          PillBadge(
                            text: cartoon.source.displayName,
                            backgroundColor: cs.surfaceContainerLow,
                            foregroundColor: cs.onSurfaceVariant,
                          ),
                          if (manager.isFetchingEpisodes) ...<Widget>[
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            Text(
                              '正在加载剧集...',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ] else ...<Widget>[
                            PillBadge(
                              text: '共 ${manager.episodes.length} 集',
                              backgroundColor: cs.secondaryContainer,
                              foregroundColor: cs.onSecondaryContainer,
                            ),
                            if (manager.selectedEpisodes.isNotEmpty)
                              PillBadge(
                                text: '已选 ${manager.selectedEpisodes.length} 集',
                                backgroundColor: cs.primaryContainer,
                                foregroundColor: cs.onPrimaryContainer,
                              ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(widget.isDesktop ? 20 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '画质配置',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            ChoiceChip(
                              label: const Text('最高画质 (默认)'),
                              selected: manager.selectedResolutionHeight == null,
                              onSelected: (_) =>
                                  manager.setSelectedResolutionHeight(null),
                            ),
                            if (manager.isFetchingResolutions)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Text(
                                  '解析画质选项中...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              )
                            else
                              ...manager.resolutionOptions.map(
                                (opt) => ChoiceChip(
                                  label: Text(opt.label),
                                  selected: manager.selectedResolutionHeight ==
                                      opt.height,
                                  onSelected: (_) =>
                                      manager.setSelectedResolutionHeight(
                                    opt.height,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (manager.episodes.isNotEmpty) ...<Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('单选'),
                          selected: !_multiSelectMode,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() => _multiSelectMode = false);
                            if (manager.selectedEpisodes.length > 1) {
                              final first = manager.selectedEpisodes.first;
                              manager.deselectAllEpisodes();
                              manager.toggleEpisodeSelection(first);
                            }
                          },
                        ),
                        ChoiceChip(
                          label: const Text('多选'),
                          selected: _multiSelectMode,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _multiSelectMode = true),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            setState(() => _multiSelectMode = true);
                            manager.selectAllEpisodes(seasonEps);
                          },
                          child: const Text('全选'),
                        ),
                        OutlinedButton(
                          onPressed: manager.deselectAllEpisodes,
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (seasons.length > 1) ...<Widget>[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: seasons.map((season) {
                            final clean = season.split('【').first;
                            final label = clean.isEmpty ? '正片' : clean;
                            final isCurrent = activeSeason == season;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: isCurrent,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedSeason = season;
                                  });
                                  manager.updateResolutionOptionsForSeason(
                                    season,
                                  );
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    LayoutBuilder(
                      builder: (context, epConstraints) {
                        const spacing = 8.0;
                        final itemWidth = widget.isDesktop
                            ? 58.0
                            : ((epConstraints.maxWidth - spacing * 4) / 5)
                                .clamp(52.0, 88.0);
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: List<Widget>.generate(seasonEps.length, (i) {
                            final ep = seasonEps[i];
                            final selected =
                                manager.selectedEpisodes.contains(ep.epNum);
                            final displayNum = i + 1;
                            return Tooltip(
                              message: ep.title,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  if (_multiSelectMode) {
                                    manager.toggleEpisodeSelection(ep.epNum);
                                  } else {
                                    final wasSelected = manager
                                        .selectedEpisodes
                                        .contains(ep.epNum);
                                    manager.deselectAllEpisodes();
                                    if (!wasSelected) {
                                      manager.toggleEpisodeSelection(ep.epNum);
                                    }
                                  }
                                },
                                child: Container(
                                  width: itemWidth,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? cs.primary
                                        : cs.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected
                                          ? cs.primary
                                          : cs.outlineVariant
                                              .withValues(alpha: 0.7),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '$displayNum',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                      fontWeight: selected
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: selected
                                          ? cs.onPrimary
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (manager.episodes.isNotEmpty) ...<Widget>[
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isDesktop ? 24 : 16,
                vertical: widget.isDesktop ? 12 : 10,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    '已选 ${manager.selectedEpisodes.length} 集',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: manager.selectedEpisodes.isEmpty
                        ? null
                        : () {
                            manager.startDownloads();
                            widget.onStartDownloadPressed();
                          },
                    icon: const Icon(Icons.download),
                    label: Text(
                      '开始下载 (${manager.selectedEpisodes.length})',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
