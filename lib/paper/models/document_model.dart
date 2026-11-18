class LanguageInfo {
  final String code;
  final String name;
  final String nativeName;
  final String flag;
  final bool isRtl;

  const LanguageInfo({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
    this.isRtl = false,
  });

  static const List<LanguageInfo> supportedLanguages = [
    LanguageInfo(code: 'en', name: 'English', nativeName: 'English', flag: '🇺🇸'),
    LanguageInfo(code: 'bn', name: 'Bengali', nativeName: 'বাংলা', flag: '🇧🇩'),
    LanguageInfo(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी', flag: '🇮🇳'),
    LanguageInfo(code: 'es', name: 'Spanish', nativeName: 'Español', flag: '🇪🇸'),
    LanguageInfo(code: 'ar', name: 'Arabic', nativeName: 'العربية', flag: '🇸🇦', isRtl: true),
    LanguageInfo(code: 'fr', name: 'French', nativeName: 'Français', flag: '🇫🇷'),
    LanguageInfo(code: 'de', name: 'German', nativeName: 'Deutsch', flag: '🇩🇪'),
    LanguageInfo(code: 'zh', name: 'Chinese', nativeName: '中文 (简体)', flag: '🇨🇳'),
    LanguageInfo(code: 'ja', name: 'Japanese', nativeName: '日本語', flag: '🇯🇵'),
    LanguageInfo(code: 'ru', name: 'Russian', nativeName: 'Русский', flag: '🇷🇺'),
    LanguageInfo(code: 'pt', name: 'Portuguese', nativeName: 'Português', flag: '🇧🇷'),
    LanguageInfo(code: 'id', name: 'Indonesian', nativeName: 'Bahasa Indonesia', flag: '🇮🇩'),
    LanguageInfo(code: 'ur', name: 'Urdu', nativeName: 'اردو', flag: '🇵🇰', isRtl: true),
  ];

  static LanguageInfo find(String code) {
    return supportedLanguages.firstWhere(
      (lang) => lang.code.toLowerCase() == code.toLowerCase(),
      orElse: () => supportedLanguages.first,
    );
  }
}

enum BlockType {
  heading,
  subheading,
  paragraph,
  bullet,
  callout,
  image,
  video,
  step,
  quote,
}

enum CalloutType {
  tip,
  warning,
  info,
  keyMetric,
}

class PaperBlock {
  final BlockType type;
  final String text;
  final String? subtitle;
  final CalloutType calloutType;
  final String? assetPath;
  final String? caption;
  final int? stepNumber;

  const PaperBlock({
    required this.type,
    this.text = '',
    this.subtitle,
    this.calloutType = CalloutType.tip,
    this.assetPath,
    this.caption,
    this.stepNumber,
  });

  factory PaperBlock.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? 'paragraph').toString().toLowerCase();
    BlockType bType = BlockType.paragraph;
    switch (typeStr) {
      case 'heading':
        bType = BlockType.heading;
        break;
      case 'subheading':
        bType = BlockType.subheading;
        break;
      case 'bullet':
        bType = BlockType.bullet;
        break;
      case 'callout':
        bType = BlockType.callout;
        break;
      case 'image':
        bType = BlockType.image;
        break;
      case 'video':
        bType = BlockType.video;
        break;
      case 'step':
        bType = BlockType.step;
        break;
      case 'quote':
        bType = BlockType.quote;
        break;
      default:
        bType = BlockType.paragraph;
    }

    final calloutStr = (json['callout_type'] ?? 'tip').toString().toLowerCase();
    CalloutType cType = CalloutType.tip;
    if (calloutStr == 'warning') cType = CalloutType.warning;
    if (calloutStr == 'info') cType = CalloutType.info;
    if (calloutStr == 'key_metric' || calloutStr == 'keymetric') cType = CalloutType.keyMetric;

    return PaperBlock(
      type: bType,
      text: json['text']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      calloutType: cType,
      assetPath: json['asset_path']?.toString() ?? json['image']?.toString(),
      caption: json['caption']?.toString(),
      stepNumber: json['step'] is int ? json['step'] as int : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'text': text,
      if (subtitle != null) 'subtitle': subtitle,
      if (type == BlockType.callout) 'callout_type': calloutType.name,
      if (assetPath != null) 'asset_path': assetPath,
      if (caption != null) 'caption': caption,
      if (stepNumber != null) 'step': stepNumber,
    };
  }
}

class PaperSection {
  final String id;
  final String title;
  final String? subtitle;
  final String category;
  final String icon;
  final List<PaperBlock> blocks;

  const PaperSection({
    required this.id,
    required this.title,
    this.subtitle,
    required this.category,
    required this.icon,
    required this.blocks,
  });

  factory PaperSection.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'] as List<dynamic>? ?? [];
    final blocks = rawBlocks
        .map((b) => PaperBlock.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();

    return PaperSection(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      category: json['category']?.toString() ?? 'General',
      icon: json['icon']?.toString() ?? 'description',
      blocks: blocks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      'category': category,
      'icon': icon,
      'blocks': blocks.map((b) => b.toJson()).toList(),
    };
  }
}

class PaperDocument {
  final String languageCode;
  final String languageName;
  final String docTitle;
  final String docSubtitle;
  final String searchPlaceholder;
  final List<PaperSection> sections;

  const PaperDocument({
    required this.languageCode,
    required this.languageName,
    required this.docTitle,
    required this.docSubtitle,
    required this.searchPlaceholder,
    required this.sections,
  });

  factory PaperDocument.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'] as List<dynamic>? ?? [];
    final sections = rawSections
        .map((s) => PaperSection.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();

    return PaperDocument(
      languageCode: json['language_code']?.toString() ?? 'en',
      languageName: json['language_name']?.toString() ?? 'English',
      docTitle: json['doc_title']?.toString() ?? 'DayAura Paper',
      docSubtitle: json['doc_subtitle']?.toString() ?? 'Offline User Manual & Feature Guide',
      searchPlaceholder: json['search_placeholder']?.toString() ?? 'Search features, routines...',
      sections: sections,
    );
  }
}
