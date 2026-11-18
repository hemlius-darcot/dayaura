import 'package:flutter/material.dart';
import 'screens/reader_screen.dart';
import 'services/paper_service.dart';
import 'theme/app_theme.dart';

class DayAuraPaperPage extends StatefulWidget {
  const DayAuraPaperPage({super.key});

  @override
  State<DayAuraPaperPage> createState() => _DayAuraPaperPageState();
}

class _DayAuraPaperPageState extends State<DayAuraPaperPage> {
  late final PaperService _paperService;
  late final ValueNotifier<ThemeMode> _themeNotifier;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _paperService = PaperService();
    _themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
    _paperService.addListener(_onServiceChanged);
    _init();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await _paperService.initialize();
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _paperService.removeListener(_onServiceChanged);
    _paperService.dispose();
    _themeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryGreen),
        ),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeNotifier,
      builder: (context, themeMode, _) {
        return Theme(
          data: themeMode == ThemeMode.light
              ? AppTheme.light()
              : AppTheme.dark(),
          child: ReaderScreen(
            service: _paperService,
            themeModeNotifier: _themeNotifier,
          ),
        );
      },
    );
  }
}
