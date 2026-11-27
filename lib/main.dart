import 'package:material_ui/material_ui.dart';

import 'services/download_manager.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnimeGetApp());
}

class AnimeGetApp extends StatefulWidget {
  const AnimeGetApp({super.key});

  @override
  State<AnimeGetApp> createState() => _AnimeGetAppState();
}

class _AnimeGetAppState extends State<AnimeGetApp> {
  final DownloadManager _manager = DownloadManager();

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _manager,
      builder: (context, _) {
        return MaterialApp(
          title: 'AnimeGet',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _manager.themeMode,
          home: HomeShell(manager: _manager),
        );
      },
    );
  }
}
