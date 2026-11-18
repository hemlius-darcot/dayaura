import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum NoteBlockType {
  text,
  heading, // TT (Large)
  subheading, // T (Medium)
  bullet, // • Bullet
  checkbox, // ☑ Checkbox
  image, // 🖼️ Inline Picture
}

class NoteBlock {
  NoteBlock({
    required this.type,
    String text = '',
    this.isBold = false,
    this.isItalic = false,
    this.isChecked = false,
    this.linkUrl,
    this.imagePath,
  })  : controller = TextEditingController(text: text),
        focusNode = FocusNode();

  NoteBlockType type;
  bool isBold;
  bool isItalic;
  bool isChecked;
  String? linkUrl;
  String? imagePath;
  final TextEditingController controller;
  final FocusNode focusNode;

  String get text => controller.text;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (text.isNotEmpty) 'text': text,
        if (isBold) 'isBold': true,
        if (isItalic) 'isItalic': true,
        if (isChecked) 'isChecked': true,
        if (linkUrl != null && linkUrl!.isNotEmpty) 'linkUrl': linkUrl,
        if (imagePath != null && imagePath!.isNotEmpty) 'imagePath': imagePath,
      };

  factory NoteBlock.fromJson(Map<String, dynamic> json) {
    NoteBlockType t = NoteBlockType.text;
    try {
      t = NoteBlockType.values.byName(json['type']?.toString() ?? 'text');
    } catch (_) {}
    return NoteBlock(
      type: t,
      text: json['text']?.toString() ?? '',
      isBold: json['isBold'] == true,
      isItalic: json['isItalic'] == true,
      isChecked: json['isChecked'] == true,
      linkUrl: json['linkUrl']?.toString(),
      imagePath: json['imagePath']?.toString(),
    );
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class JournalNotepadSheet extends StatefulWidget {
  const JournalNotepadSheet({
    super.key,
    required this.date,
    this.initialEmoji,
    this.initialTitle,
    this.initialNote,
    this.initialImages,
    required this.onSave,
  });

  final DateTime date;
  final String? initialEmoji;
  final String? initialTitle;
  final String? initialNote;
  final List<String>? initialImages;
  final void Function({
    required String? emoji,
    required String? title,
    required String? note,
    required List<String> images,
  }) onSave;

  @override
  State<JournalNotepadSheet> createState() => _JournalNotepadSheetState();
}

class _JournalNotepadSheetState extends State<JournalNotepadSheet> {
  late TextEditingController _titleController;
  String? _selectedEmoji;
  final List<NoteBlock> _blocks = [];
  int _activeBlockIndex = 0;

  static const List<String> _quickEmojis = [
    '⭐', '🎓', '🏆', '❤️', '🎂', '🚀', '💡', '📝',
    '🔥', '🏖️', '💻', '🎯', '🎉', '📚', '🩺', '✈️',
    '💪', '🌟', '💼', '🥇'
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _selectedEmoji = widget.initialEmoji;
    _initBlocks();
  }

  void _initBlocks() {
    final note = widget.initialNote?.trim() ?? '';
    if (note.startsWith('{"version":')) {
      try {
        final decoded = jsonDecode(note);
        if (decoded is Map && decoded['blocks'] is List) {
          for (final b in decoded['blocks']) {
            if (b is Map) {
              _blocks.add(NoteBlock.fromJson(Map<String, dynamic>.from(b)));
            }
          }
        }
      } catch (_) {}
    }

    if (_blocks.isEmpty) {
      if (note.isNotEmpty) {
        final lines = note.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed.startsWith('# ')) {
            _blocks.add(NoteBlock(
              type: NoteBlockType.heading,
              text: trimmed.substring(2).trim(),
            ));
          } else if (trimmed.startsWith('## ')) {
            _blocks.add(NoteBlock(
              type: NoteBlockType.subheading,
              text: trimmed.substring(3).trim(),
            ));
          } else if (trimmed.startsWith('• ') || trimmed.startsWith('- ')) {
            _blocks.add(NoteBlock(
              type: NoteBlockType.bullet,
              text: trimmed.substring(2).trim(),
            ));
          } else if (trimmed.startsWith('✓ ') || trimmed.startsWith('[x] ')) {
            _blocks.add(NoteBlock(
              type: NoteBlockType.checkbox,
              text: trimmed.substring(trimmed.indexOf(' ') + 1).trim(),
              isChecked: true,
            ));
          } else if (trimmed.startsWith('[ ] ')) {
            _blocks.add(NoteBlock(
              type: NoteBlockType.checkbox,
              text: trimmed.substring(4).trim(),
              isChecked: false,
            ));
          } else {
            var isB = false;
            var isI = false;
            var cleanText = trimmed;
            if (cleanText.startsWith('**') && cleanText.endsWith('**') && cleanText.length > 4) {
              cleanText = cleanText.substring(2, cleanText.length - 2).trim();
              isB = true;
            }
            if (cleanText.startsWith('*') && cleanText.endsWith('*') && cleanText.length > 2) {
              cleanText = cleanText.substring(1, cleanText.length - 1).trim();
              isI = true;
            }
            _blocks.add(NoteBlock(
              type: NoteBlockType.text,
              text: cleanText,
              isBold: isB,
              isItalic: isI,
            ));
          }
        }
      }

      // Add any legacy images from initialImages if not already present
      if (widget.initialImages != null) {
        for (final img in widget.initialImages!) {
          if (!_blocks.any((b) => b.imagePath == img)) {
            _blocks.add(NoteBlock(
              type: NoteBlockType.image,
              imagePath: img,
            ));
          }
        }
      }
    }

    if (_blocks.isEmpty) {
      _blocks.add(NoteBlock(type: NoteBlockType.text));
    }

    _activeBlockIndex = 0;
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  NoteBlock get _currentBlock {
    if (_activeBlockIndex >= 0 && _activeBlockIndex < _blocks.length) {
      return _blocks[_activeBlockIndex];
    }
    return _blocks.first;
  }

  void _toggleBold() {
    setState(() {
      _currentBlock.isBold = !_currentBlock.isBold;
    });
  }

  void _toggleItalic() {
    setState(() {
      _currentBlock.isItalic = !_currentBlock.isItalic;
    });
  }

  void _toggleHeading() {
    setState(() {
      if (_currentBlock.type == NoteBlockType.heading) {
        _currentBlock.type = NoteBlockType.text;
      } else {
        _currentBlock.type = NoteBlockType.heading;
      }
    });
  }

  void _toggleSubheading() {
    setState(() {
      if (_currentBlock.type == NoteBlockType.subheading) {
        _currentBlock.type = NoteBlockType.text;
      } else {
        _currentBlock.type = NoteBlockType.subheading;
      }
    });
  }

  void _toggleBullet() {
    setState(() {
      if (_currentBlock.type == NoteBlockType.bullet) {
        _currentBlock.type = NoteBlockType.text;
      } else {
        _currentBlock.type = NoteBlockType.bullet;
      }
    });
  }

  void _toggleCheckbox() {
    setState(() {
      if (_currentBlock.type == NoteBlockType.checkbox) {
        _currentBlock.type = NoteBlockType.text;
      } else {
        _currentBlock.type = NoteBlockType.checkbox;
      }
    });
  }

  Future<void> _promptInsertLink() async {
    final textController =
        TextEditingController(text: _currentBlock.text.isNotEmpty ? _currentBlock.text : '');
    final urlController =
        TextEditingController(text: _currentBlock.linkUrl ?? 'https://');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insert Clickable Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Display Text / Word',
                hintText: 'e.g. Physics Result Page',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Web Link (URL)',
                hintText: 'https://example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply Link'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final label = textController.text.trim();
      final url = urlController.text.trim();
      setState(() {
        if (label.isNotEmpty) {
          _currentBlock.controller.text = label;
        }
        _currentBlock.linkUrl = url.isNotEmpty ? url : null;
      });
    }
  }

  Future<void> _pickAndInsertImageInline() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isNotEmpty) {
        final docDir = await getApplicationDocumentsDirectory();
        final journalDir = Directory('${docDir.path}/journal_images');
        if (!await journalDir.exists()) {
          await journalDir.create(recursive: true);
        }

        for (final file in files) {
          if (file.path != null) {
            final srcFile = File(file.path!);
            final fileName =
                'img_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
            final destFile = File('${journalDir.path}/$fileName');
            await srcFile.copy(destFile.path);

            setState(() {
              // Insert image block immediately below current active block
              final insertIndex = (_activeBlockIndex + 1).clamp(0, _blocks.length);
              _blocks.insert(
                insertIndex,
                NoteBlock(
                  type: NoteBlockType.image,
                  imagePath: destFile.path,
                ),
              );

              // Followed by a fresh text block below the image so user continues typing
              final nextTextBlock = NoteBlock(type: NoteBlockType.text);
              _blocks.insert(insertIndex + 1, nextTextBlock);
              _activeBlockIndex = insertIndex + 1;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) nextTextBlock.focusNode.requestFocus();
              });
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _addNewLineBelow([int? atIndex]) {
    final target = atIndex ?? _activeBlockIndex;
    final insertPos = (target + 1).clamp(0, _blocks.length);
    final prevType = _blocks[target].type;
    // Inherit list types (bullet, checkbox)
    final inheritType = (prevType == NoteBlockType.bullet || prevType == NoteBlockType.checkbox)
        ? prevType
        : NoteBlockType.text;

    final newBlock = NoteBlock(type: inheritType);
    setState(() {
      _blocks.insert(insertPos, newBlock);
      _activeBlockIndex = insertPos;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) newBlock.focusNode.requestFocus();
    });
  }

  void _removeBlock(int index) {
    if (_blocks.length <= 1) {
      setState(() {
        _blocks[0].controller.clear();
        _blocks[0].type = NoteBlockType.text;
        _blocks[0].imagePath = null;
        _blocks[0].linkUrl = null;
      });
      return;
    }

    setState(() {
      final removed = _blocks.removeAt(index);
      removed.dispose();
      _activeBlockIndex = (_activeBlockIndex - 1).clamp(0, _blocks.length - 1);
    });
  }

  void _saveAndExit() {
    final images = <String>[];
    for (final b in _blocks) {
      if (b.type == NoteBlockType.image && b.imagePath != null && b.imagePath!.isNotEmpty) {
        images.add(b.imagePath!);
      }
    }

    final hasAnyText = _blocks.any((b) => b.text.trim().isNotEmpty);
    final hasImages = images.isNotEmpty;

    final noteJson = (hasAnyText || hasImages)
        ? jsonEncode({
            'version': 2,
            'blocks': _blocks.map((b) => b.toJson()).toList(),
          })
        : null;

    widget.onSave(
      emoji: _selectedEmoji?.trim().isEmpty == true ? null : _selectedEmoji?.trim(),
      title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
      note: noteJson,
      images: images,
    );

    Navigator.pop(context);
  }

  void _showEmojiPickerSheet() {
    final customEmojiController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Graph Badge Emoji / Symbol',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _quickEmojis.map((emoji) {
                final isSelected = _selectedEmoji == emoji;
                return InkWell(
                  onTap: () {
                    setState(() => _selectedEmoji = emoji);
                    Navigator.pop(ctx);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5,
                            )
                          : null,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customEmojiController,
                    decoration: const InputDecoration(
                      hintText: 'Or type custom emoji / text / letter (A, 1, 🎓)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final text = customEmojiController.text.trim();
                    if (text.isNotEmpty) {
                      setState(() => _selectedEmoji = text);
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Set'),
                ),
              ],
            ),
            if (_selectedEmoji != null) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: const Text('Remove Badge Emoji',
                      style: TextStyle(color: Colors.redAccent)),
                  onPressed: () {
                    setState(() => _selectedEmoji = null);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDockedToolbar() {
    final block = _currentBlock;
    final isBold = block.isBold;
    final isItalic = block.isItalic;
    final isHeading = block.type == NoteBlockType.heading;
    final isSubheading = block.type == NoteBlockType.subheading;
    final isBullet = block.type == NoteBlockType.bullet;
    final isCheckbox = block.type == NoteBlockType.checkbox;
    final hasLink = block.linkUrl != null && block.linkUrl!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolbarButton(
              label: 'B',
              isActive: isBold,
              isBoldText: true,
              tooltip: 'Bold text',
              onTap: _toggleBold,
            ),
            _toolbarButton(
              label: 'I',
              isActive: isItalic,
              isItalicText: true,
              tooltip: 'Italic text',
              onTap: _toggleItalic,
            ),
            _toolbarButton(
              label: 'TT',
              isActive: isHeading,
              tooltip: 'Large Heading (TT)',
              onTap: _toggleHeading,
            ),
            _toolbarButton(
              label: 'T',
              isActive: isSubheading,
              tooltip: 'Medium Subheading (T)',
              onTap: _toggleSubheading,
            ),
            _toolbarIconButton(
              icon: Icons.format_list_bulleted_rounded,
              isActive: isBullet,
              tooltip: 'Bullet list',
              onTap: _toggleBullet,
            ),
            _toolbarIconButton(
              icon: Icons.check_box_outlined,
              isActive: isCheckbox,
              tooltip: 'Checklist task',
              onTap: _toggleCheckbox,
            ),
            _toolbarIconButton(
              icon: Icons.link_rounded,
              isActive: hasLink,
              tooltip: 'Insert clickable link',
              onTap: _promptInsertLink,
            ),
            _toolbarIconButton(
              icon: Icons.add_photo_alternate_rounded,
              isActive: false,
              tooltip: 'Insert Picture below current line',
              activeColor: Colors.tealAccent,
              onTap: _pickAndInsertImageInline,
            ),
            IconButton(
              tooltip: 'Add new line / block',
              icon: const Icon(Icons.keyboard_return_rounded, size: 20),
              onPressed: () => _addNewLineBelow(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required String label,
    required bool isActive,
    bool isBoldText = false,
    bool isItalicText = false,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBoldText ? FontWeight.bold : FontWeight.w600,
              fontStyle: isItalicText ? FontStyle.italic : FontStyle.normal,
              color: isActive
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbarIconButton({
    required IconData icon,
    required bool isActive,
    required String tooltip,
    Color? activeColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
                : null,
          ),
          child: Icon(
            icon,
            size: 19,
            color: isActive
                ? (activeColor ?? Theme.of(context).colorScheme.primary)
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildBlockItem(int index) {
    final block = _blocks[index];

    if (block.type == NoteBlockType.image) {
      final file = File(block.imagePath ?? '');
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 280),
                color: Colors.grey.withValues(alpha: 0.15),
                child: file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover)
                    : const Padding(
                        padding: EdgeInsets.all(24),
                        child: Icon(Icons.broken_image, size: 40),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: () => _removeBlock(index),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Determine font styles based on block properties
    TextStyle textStyle;
    switch (block.type) {
      case NoteBlockType.heading:
        textStyle = TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
        );
        break;
      case NoteBlockType.subheading:
        textStyle = TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Colors.tealAccent,
          fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
        );
        break;
      case NoteBlockType.checkbox:
        textStyle = TextStyle(
          fontSize: 14,
          fontWeight: block.isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
          decoration: block.isChecked ? TextDecoration.lineThrough : null,
          color: block.isChecked ? Colors.grey : null,
        );
        break;
      default:
        textStyle = TextStyle(
          fontSize: 14,
          height: 1.4,
          fontWeight: block.isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: block.isItalic ? FontStyle.italic : FontStyle.normal,
        );
        break;
    }

    if (block.linkUrl != null && block.linkUrl!.isNotEmpty) {
      textStyle = textStyle.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      );
    }

    Widget leadingWidget = const SizedBox.shrink();
    if (block.type == NoteBlockType.checkbox) {
      leadingWidget = Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: block.isChecked,
            visualDensity: VisualDensity.compact,
            onChanged: (val) {
              setState(() {
                block.isChecked = val ?? false;
              });
            },
          ),
        ),
      );
    } else if (block.type == NoteBlockType.bullet) {
      leadingWidget = const Padding(
        padding: EdgeInsets.only(right: 8, top: 4),
        child: Text('•', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leadingWidget,
          Expanded(
            child: TextField(
              controller: block.controller,
              focusNode: block.focusNode,
              maxLines: null,
              style: textStyle,
              decoration: InputDecoration(
                hintText: index == 0 && _blocks.length == 1
                    ? 'Start typing your memorable note here...\n• Tap B, I, TT, T, •, ☑ below for live styling\n• Tap 🖼️ to insert photo right below this line'
                    : (block.type == NoteBlockType.heading
                        ? 'Heading text...'
                        : (block.type == NoteBlockType.checkbox ? 'Task / checklist...' : 'Type...')),
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              onTap: () {
                setState(() => _activeBlockIndex = index);
              },
              onSubmitted: (_) {
                _addNewLineBelow(index);
              },
            ),
          ),
          if (block.linkUrl != null && block.linkUrl!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 16, color: Colors.teal),
              tooltip: 'Open Link: ${block.linkUrl}',
              onPressed: () async {
                final uri = Uri.tryParse(block.linkUrl!);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text('Memorable Day Note ($dateStr)'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Save'),
              onPressed: _saveAndExit,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Title & Badge Emoji Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: _showEmojiPickerSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.4),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedEmoji ?? '🏷️',
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Memory Note Title',
                        hintText: 'e.g. Physics Exam, Admission Result',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Live WYSIWYG Document Editor Body
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _blocks.length,
                itemBuilder: (ctx, index) => _buildBlockItem(index),
              ),
            ),

            // Formatting toolbar docked directly above keyboard with zero empty gap
            _buildDockedToolbar(),
          ],
        ),
      ),
    );
  }
}
