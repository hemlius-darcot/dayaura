import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/document_model.dart';

class PaperService extends ChangeNotifier {
  static const String _prefLangKey = 'dayaura_paper_selected_language';
  
  LanguageInfo _currentLanguage = LanguageInfo.find('en');
  PaperDocument? _document;
  bool _isLoading = true;
  String? _errorMessage;

  final Map<String, PaperDocument> _cache = {};

  LanguageInfo get currentLanguage => _currentLanguage;
  PaperDocument? get document => _document;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_prefLangKey) ?? 'en';
      _currentLanguage = LanguageInfo.find(savedCode);
    } catch (_) {
      _currentLanguage = LanguageInfo.find('en');
    }

    await loadLanguage(_currentLanguage.code);
  }

  Future<void> selectLanguage(LanguageInfo language) async {
    if (_currentLanguage.code == language.code && _document != null) {
      return;
    }

    _currentLanguage = language;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLangKey, language.code);
    } catch (e) {
      debugPrint('Failed to save language preference: $e');
    }

    await loadLanguage(language.code);
  }

  Future<void> loadLanguage(String code) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Check cache first
    if (_cache.containsKey(code)) {
      _document = _cache[code];
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final assetPath = 'assets/docs/$code.json';
      final jsonString = await rootBundle.loadString(assetPath);
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      final doc = PaperDocument.fromJson(jsonMap);

      _cache[code] = doc;
      _document = doc;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading document for $code: $e');
      // If requested language json is not found, fallback to 'en'
      if (code != 'en') {
        try {
          const fallbackPath = 'assets/docs/en.json';
          final jsonString = await rootBundle.loadString(fallbackPath);
          final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
          final doc = PaperDocument.fromJson(jsonMap);
          _document = doc;
          _isLoading = false;
          notifyListeners();
          return;
        } catch (inner) {
          _errorMessage = 'Failed to load fallback documentation: $inner';
        }
      } else {
        _errorMessage = 'Failed to load documentation ($code): $e';
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  List<PaperSection> search(String query) {
    if (_document == null || query.trim().isEmpty) {
      return _document?.sections ?? [];
    }

    final q = query.trim().toLowerCase();
    return _document!.sections.where((section) {
      if (section.title.toLowerCase().contains(q)) return true;
      if (section.subtitle?.toLowerCase().contains(q) ?? false) return true;
      if (section.category.toLowerCase().contains(q)) return true;

      for (final block in section.blocks) {
        if (block.text.toLowerCase().contains(q)) return true;
        if (block.subtitle?.toLowerCase().contains(q) ?? false) return true;
        if (block.caption?.toLowerCase().contains(q) ?? false) return true;
      }
      return false;
    }).toList();
  }
}
