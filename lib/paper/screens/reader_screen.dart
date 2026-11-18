import 'package:flutter/material.dart';
import '../models/document_model.dart';
import '../services/paper_service.dart';
import '../theme/app_theme.dart';
import '../widgets/journal_block_view.dart';
import '../widgets/language_selector_sheet.dart';

class ReaderScreen extends StatefulWidget {
  final PaperService service;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  const ReaderScreen({
    super.key,
    required this.service,
    required this.themeModeNotifier,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.offset > 400 && !_showBackToTop) {
      setState(() => _showBackToTop = true);
    } else if (_scrollController.offset <= 400 && _showBackToTop) {
      setState(() => _showBackToTop = false);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final doc = widget.service.document;
    final isRtl = widget.service.currentLanguage.isRtl;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF111713) : const Color(0xFFFFFFFF),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF111713) : const Color(0xFFFFFFFF),
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: const BackButton(),
          titleSpacing: 0,
          title: Text(
            doc?.docTitle ?? 'DayAura Paper',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
          ),
          actions: [
            // Language Selector Button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF1C241E) : const Color(0xFFF1F5F2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () => LanguageSelectorSheet.show(context, widget.service),
                icon: Text(widget.service.currentLanguage.flag, style: const TextStyle(fontSize: 15)),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.service.currentLanguage.nativeName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // Theme Switch
            IconButton(
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 20,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
              tooltip: isDark ? 'Light Mode' : 'Dark Mode',
              onPressed: () {
                widget.themeModeNotifier.value =
                    isDark ? ThemeMode.light : ThemeMode.dark;
              },
            ),
            const SizedBox(width: 8),
          ],
        ),

        // Document Body
        body: widget.service.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGreen),
              )
            : widget.service.errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        widget.service.errorMessage!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _buildPaperDocument(context, isDark, doc),

        // Floating Back to Top Button
        floatingActionButton: _showBackToTop
            ? FloatingActionButton.small(
                onPressed: _scrollToTop,
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                child: const Icon(Icons.arrow_upward_rounded, size: 20),
              )
            : null,
      ),
    );
  }

  Widget _buildPaperDocument(
    BuildContext context,
    bool isDark,
    PaperDocument? doc,
  ) {
    if (doc == null) return const SizedBox.shrink();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          children: [
            // Document Header
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
              child: Text(
                doc.docTitle,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.25,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
                softWrap: true,
              ),
            ),

            if (doc.docSubtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  doc.docSubtitle,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                  softWrap: true,
                ),
              ),

            Divider(
              height: 24,
              thickness: 1,
              color: isDark ? const Color(0xFF222C24) : const Color(0xFFE5EBE7),
            ),

            // Continuous Document Sections
            for (int i = 0; i < doc.sections.length; i++) ...[
              _buildSection(context, isDark, doc.sections[i]),
              if (i < doc.sections.length - 1)
                Divider(
                  height: 36,
                  thickness: 1,
                  color: isDark ? const Color(0xFF1E2820) : const Color(0xFFEEF2EF),
                ),
            ],

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    bool isDark,
    PaperSection section,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title (Clean, wrapped, no overflow risk)
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
          child: Text(
            section.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.35,
              color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF1B231D),
            ),
            softWrap: true,
          ),
        ),

        // Section Subtitle
        if (section.subtitle != null && section.subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              section.subtitle!,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
              softWrap: true,
            ),
          ),

        const SizedBox(height: 4),

        // Section Blocks
        for (final block in section.blocks)
          JournalBlockView(block: block),
      ],
    );
  }
}
