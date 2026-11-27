import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/anime_models.dart';
import '../services/download_manager.dart';
import 'search_view.dart';
import 'settings_view.dart';
import 'tasks_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.manager});

  final DownloadManager manager;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  bool _showMobileTaskDetail = false;
  DateTime? _lastBackPressedAt;

  void _handleBackNavigation(BuildContext context, bool isDesktop) {
    final manager = widget.manager;

    if (!isDesktop && _selectedIndex == 0 && manager.selectedCartoon != null) {
      manager.clearSelectedCartoon();
      return;
    }

    if (!isDesktop && _selectedIndex == 1 && _showMobileTaskDetail) {
      setState(() => _showMobileTaskDetail = false);
      return;
    }

    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
        _showMobileTaskDetail = false;
      });
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('再按一次返回桌面'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manager = widget.manager;
    final activeOrQueuedCount = manager.downloadTasks
        .where((t) => t.isActive || t.phase == DownloadPhase.queued)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        final bodyContent = AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey<int>(_selectedIndex),
            child: switch (_selectedIndex) {
              0 => SearchPane(
                  manager: manager,
                  isDesktop: isDesktop,
                  onStartDownloadPressed: () {
                    setState(() {
                      _selectedIndex = 1;
                      _showMobileTaskDetail = false;
                    });
                  },
                ),
              1 => TasksPane(
                  manager: manager,
                  isDesktop: isDesktop,
                  showMobileDetail: _showMobileTaskDetail,
                  onMobileDetailChanged: (show) =>
                      setState(() => _showMobileTaskDetail = show),
                ),
              _ => SettingsPane(
                  manager: manager,
                  isDesktop: isDesktop,
                ),
            },
          ),
        );

        final scaffold = isDesktop
            ? Scaffold(
                body: Column(
                  children: <Widget>[
                    _buildTopAppBar(context, activeOrQueuedCount),
                    Expanded(child: bodyContent),
                  ],
                ),
              )
            : Scaffold(
                appBar: AppBar(
                  backgroundColor: cs.surface,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  shape: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                  title: Row(
                    children: <Widget>[
                      _brandIcon(context, size: 30),
                      const SizedBox(width: 10),
                      const Text(
                        'AnimeGet',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    if (activeOrQueuedCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.arrow_downward,
                              size: 12,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              manager.currentDownloadSpeedString,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    IconButton(
                      icon: Icon(_themeModeIcon(manager.themeMode)),
                      tooltip: _themeModeTooltip(manager.themeMode),
                      onPressed: manager.cycleThemeMode,
                    ),
                  ],
                ),
                body: bodyContent,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (idx) => setState(() {
                    _selectedIndex = idx;
                    if (idx != 1) {
                      _showMobileTaskDetail = false;
                    }
                  }),
                  destinations: <NavigationDestination>[
                    const NavigationDestination(
                      icon: Icon(Icons.search),
                      label: '搜索',
                    ),
                    NavigationDestination(
                      icon: activeOrQueuedCount > 0
                          ? Badge.count(
                              count: activeOrQueuedCount,
                              child: const Icon(Icons.download_outlined),
                            )
                          : const Icon(Icons.download_outlined),
                      selectedIcon: activeOrQueuedCount > 0
                          ? Badge.count(
                              count: activeOrQueuedCount,
                              child: const Icon(Icons.download),
                            )
                          : const Icon(Icons.download),
                      label: '任务',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: '设置',
                    ),
                  ],
                ),
              );

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _handleBackNavigation(context, isDesktop);
          },
          child: scaffold,
        );
      },
    );
  }

  Widget _brandIcon(BuildContext context, {double size = 40}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[cs.primary, cs.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.download_for_offline_rounded,
        size: size * 0.56,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTopAppBar(BuildContext context, int activeOrQueuedCount) {
    final cs = Theme.of(context).colorScheme;
    final manager = widget.manager;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          _brandIcon(context),
          const SizedBox(width: 12),
          Text(
            'AnimeGet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          _navPill(
            context,
            index: 0,
            icon: Icons.search,
            label: '搜索与选集',
          ),
          const SizedBox(width: 8),
          _navPill(
            context,
            index: 1,
            icon: Icons.download_outlined,
            label: '下载任务',
            badgeCount: activeOrQueuedCount,
          ),
          const SizedBox(width: 8),
          _navPill(
            context,
            index: 2,
            icon: Icons.settings_outlined,
            label: '系统设置',
          ),
          const SizedBox(width: 16),
          Container(
            width: 124,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_downward, size: 13, color: cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    manager.currentDownloadSpeedString,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              shape: BoxShape.circle,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: _themeModeTooltip(manager.themeMode),
              icon: Icon(
                _themeModeIcon(manager.themeMode),
                size: 19,
                color: cs.onSurface,
              ),
              onPressed: manager.cycleThemeMode,
            ),
          ),
        ],
      ),
    );
  }

  IconData _themeModeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.contrast_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };
  }

  String _themeModeTooltip(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => '主题：跟随系统 (点击切换)',
      ThemeMode.light => '主题：浅色模式 (点击切换)',
      ThemeMode.dark => '主题：深色模式 (点击切换)',
    };
  }

  Widget _navPill(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    int badgeCount = 0,
  }) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
            if (badgeCount > 0) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
