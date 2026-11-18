import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RoutineTemplate {
  RoutineTemplate({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.mode,
    required this.tasks,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final String mode; // 'Auto' or 'Manual'
  final List<Map<String, dynamic>> tasks;

  int get totalTasksCount {
    int countNodes(List<dynamic> list) {
      var count = 0;
      for (final item in list) {
        if (item is Map) {
          count++;
          final children = item['children'];
          if (children is List && children.isNotEmpty) {
            count += countNodes(children);
          }
        }
      }
      return count;
    }

    return countNodes(tasks);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'mode': mode,
        'tasks': tasks,
      };

  factory RoutineTemplate.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'];
    List<Map<String, dynamic>> taskList = [];
    if (rawTasks is List) {
      taskList = rawTasks
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return RoutineTemplate(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'Untitled Routine',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      mode: json['mode']?.toString() ?? 'Auto',
      tasks: taskList,
    );
  }
}

class RoutineTemplateStore {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/routine_favorites.json');
  }

  Future<List<RoutineTemplate>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <RoutineTemplate>[];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <RoutineTemplate>[];
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> || decoded['templates'] is! List) {
        return <RoutineTemplate>[];
      }

      final list = <RoutineTemplate>[];
      for (final item in decoded['templates'] as List) {
        if (item is Map) {
          try {
            list.add(RoutineTemplate.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return <RoutineTemplate>[];
    }
  }

  Future<void> _writeAtomic(List<RoutineTemplate> templates) async {
    final targetFile = await _file();
    final tempFile = File('${targetFile.path}.tmp');
    final payload = jsonEncode({
      'version': 1,
      'templates': templates.map((t) => t.toJson()).toList(),
    });
    await tempFile.writeAsString(payload, flush: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tempFile.rename(targetFile.path);
  }

  Future<void> save(RoutineTemplate template) async {
    final list = await load();
    final idx = list.indexWhere((t) => t.id == template.id);
    if (idx >= 0) {
      list[idx] = template;
    } else {
      list.insert(0, template);
    }
    await _writeAtomic(list);
  }

  Future<void> delete(String id) async {
    final list = await load();
    list.removeWhere((t) => t.id == id);
    await _writeAtomic(list);
  }

  /// Exports a single favorite routine to a .json file for sharing via WhatsApp/Telegram
  Future<File> exportSingleToFile(RoutineTemplate template) async {
    final tempDir = await getTemporaryDirectory();
    final cleanTitle = template.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final safeName = cleanTitle.isEmpty ? 'routine' : cleanTitle;
    final file = File('${tempDir.path}/Routine_${safeName}.json');

    final payload = jsonEncode({
      'app': 'RoutineTracker',
      'type': 'routine_template',
      'exportVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'template': template.toJson(),
    });

    await file.writeAsString(payload, flush: true);
    return file;
  }

  /// Validates an imported JSON string to see if it is a valid single RoutineTemplate
  RoutineTemplate? validateAndParseSingle(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) return null;

      if (decoded['type'] == 'routine_template' && decoded['template'] is Map) {
        return RoutineTemplate.fromJson(
          Map<String, dynamic>.from(decoded['template'] as Map),
        );
      }

      // Fallback: direct template JSON
      if (decoded['title'] is String && decoded['tasks'] is List) {
        return RoutineTemplate.fromJson(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Exports all templates to JSON list for inclusion in full backup
  Future<List<Map<String, dynamic>>> exportAllToJson() async {
    final list = await load();
    return list.map((t) => t.toJson()).toList();
  }

  /// Imports multiple templates from a full backup, preserving existing ones
  Future<int> importMultiple(List<Map<String, dynamic>> rawTemplates) async {
    final currentList = await load();
    var addedCount = 0;
    for (final raw in rawTemplates) {
      try {
        final t = RoutineTemplate.fromJson(raw);
        if (!currentList.any((existing) => existing.id == t.id || existing.title == t.title)) {
          currentList.add(t);
          addedCount++;
        }
      } catch (_) {}
    }
    if (addedCount > 0) {
      await _writeAtomic(currentList);
    }
    return addedCount;
  }
}
