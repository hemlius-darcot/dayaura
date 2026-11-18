import 'package:flutter/material.dart';
import '../models/document_model.dart';
import '../services/paper_service.dart';
import '../theme/app_theme.dart';

class LanguageSelectorSheet extends StatefulWidget {
  final PaperService service;

  const LanguageSelectorSheet({
    super.key,
    required this.service,
  });

  static Future<void> show(BuildContext context, PaperService service) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LanguageSelectorSheet(service: service),
    );
  }

  @override
  State<LanguageSelectorSheet> createState() => _LanguageSelectorSheetState();
}

class _LanguageSelectorSheetState extends State<LanguageSelectorSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filtered = LanguageInfo.supportedLanguages.where((lang) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return lang.name.toLowerCase().contains(q) ||
          lang.nativeName.toLowerCase().contains(q) ||
          lang.code.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
            child: Row(
              children: [
                const Icon(Icons.language_rounded, color: AppTheme.primaryGreen),
                const SizedBox(width: 10),
                Text(
                  'Select Language',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search language (বাংলা, English, Español...)',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: isDark ? AppTheme.darkCard : const Color(0xFFF0F4F1),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const Divider(height: 16),

          // List of Languages
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: isDark ? AppTheme.darkBorder.withValues(alpha: 0.5) : AppTheme.lightBorder,
              ),
              itemBuilder: (context, index) {
                final lang = filtered[index];
                final isSelected = widget.service.currentLanguage.code == lang.code;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  leading: Text(
                    lang.flag,
                    style: const TextStyle(fontSize: 26),
                  ),
                  title: Row(
                    children: [
                      Text(
                        lang.nativeName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryGreen
                              : (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${lang.name})',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen)
                      : null,
                  onTap: () {
                    widget.service.selectLanguage(lang);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
