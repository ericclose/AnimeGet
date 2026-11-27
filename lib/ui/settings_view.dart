import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../services/download_manager.dart';
import 'widgets/common_widgets.dart';

class SettingsPane extends StatelessWidget {
  const SettingsPane({
    super.key,
    required this.manager,
    this.isDesktop = true,
  });

  final DownloadManager manager;
  final bool isDesktop;

  Future<void> _pickDirectory(BuildContext context) async {
    final path = await getDirectoryPath(
      initialDirectory: manager.downloadDirectoryPath,
    );
    if (path != null && path.isNotEmpty) {
      await manager.setDownloadDirectory(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1360),
        child: ListView(
          padding: EdgeInsets.all(isDesktop ? 24 : 14),
          children: <Widget>[
            Text(
              '系统设置',
              style: (isDesktop
                      ? Theme.of(context).textTheme.headlineMedium
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: isDesktop ? 20 : 14),
            Card(
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 20 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '下载目录',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: isDesktop
                          ? Row(
                              children: <Widget>[
                                Icon(
                                  Icons.folder_outlined,
                                  size: 18,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    manager.downloadDirectoryPath.isEmpty
                                        ? '正在获取默认目录...'
                                        : manager.downloadDirectoryPath,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.tonalIcon(
                                  onPressed: () => _pickDirectory(context),
                                  icon: const Icon(Icons.folder_open, size: 16),
                                  label: const Text('更改目录'),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.folder_outlined,
                                        size: 18,
                                        color: cs.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        manager.downloadDirectoryPath.isEmpty
                                            ? '正在获取默认目录...'
                                            : manager.downloadDirectoryPath,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.tonalIcon(
                                    onPressed: () => _pickDirectory(context),
                                    icon: const Icon(Icons.folder_open, size: 16),
                                    label: const Text('更改目录'),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: isDesktop ? 16 : 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 20 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Text(
                          '单任务分片并发线程',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        _monoPill(context, '${manager.maxWorkers} 线程'),
                      ],
                    ),
                    Slider(
                      value: manager.maxWorkers.toDouble(),
                      min: 1,
                      max: 64,
                      divisions: 63,
                      label: '${manager.maxWorkers}',
                      onChanged: (val) => manager.setMaxWorkers(val.round()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        const Text(
                          '同时下载剧集任务数',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        _monoPill(
                          context,
                          '${manager.maxConcurrentDownloads} 任务',
                        ),
                      ],
                    ),
                    Slider(
                      value: manager.maxConcurrentDownloads.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: '${manager.maxConcurrentDownloads}',
                      onChanged: (val) =>
                          manager.setMaxConcurrentDownloads(val.round()),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: isDesktop ? 16 : 12),
            Card(
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 20 : 16),
                child: isDesktop
                    ? Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  '主题外观',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '默认跟随系统，也可手动切换浅色或深色外观',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          _buildThemeSegmentedButton(),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            '主题外观',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '默认跟随系统，也可手动切换浅色或深色外观',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: _buildThemeSegmentedButton(),
                          ),
                        ],
                      ),
              ),
            ),
            SizedBox(height: isDesktop ? 16 : 12),
            Card(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 20 : 16,
                  vertical: 14,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'AnimeGet',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      'v1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant,
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

  Widget _buildThemeSegmentedButton() {
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: isDesktop,
      segments: const <ButtonSegment<ThemeMode>>[
        ButtonSegment<ThemeMode>(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto, size: 16),
          label: Text('系统'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode, size: 16),
          label: Text('浅色'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode, size: 16),
          label: Text('深色'),
        ),
      ],
      selected: <ThemeMode>{manager.themeMode},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          manager.setThemeMode(selection.first);
        }
      },
    );
  }

  Widget _monoPill(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return PillBadge(
      text: text,
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      isMono: true,
    );
  }
}
