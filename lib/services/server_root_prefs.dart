import 'package:shared_preferences/shared_preferences.dart';

class ServerRootPrefs {
  static const String _key = 'selected_master_server_roots';
  static const String _includeKey = 'selected_master_server_prefixes';
  static const String _excludeKey = 'excluded_master_server_prefixes';

  static String? rootFromPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final idx = trimmed.indexOf('/');
    if (idx <= 0) return trimmed;
    return trimmed.substring(0, idx);
  }

  static Future<Set<String>?> getSelectedRoots() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key);
    if (list == null) return null;
    final cleaned = list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (cleaned.isEmpty) return null;
    return cleaned;
  }

  static Future<void> setSelectedRoots(Set<String>? roots) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = (roots ?? {}).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (cleaned.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    final sorted = cleaned.toList()..sort();
    await prefs.setStringList(_key, sorted);
  }

  static Future<Set<String>?> getIncludedPrefixes() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_includeKey);
    if (list != null) {
      final cleaned = list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      if (cleaned.isNotEmpty) return cleaned;
    }
    final legacyRoots = prefs.getStringList(_key);
    if (legacyRoots == null) return null;
    final cleanedLegacy = legacyRoots.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (cleanedLegacy.isEmpty) return null;
    final sorted = cleanedLegacy.toList()..sort();
    await prefs.setStringList(_includeKey, sorted);
    return cleanedLegacy;
  }

  static Future<Set<String>> getExcludedPrefixes() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_excludeKey) ?? const <String>[];
    final cleaned = list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    return cleaned;
  }

  static Future<void> setFolderRules({
    required Set<String>? includedPrefixes,
    required Set<String> excludedPrefixes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final includeClean = (includedPrefixes ?? {}).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final excludeClean = excludedPrefixes.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    if (includeClean.isEmpty) {
      await prefs.remove(_includeKey);
    } else {
      final sorted = includeClean.toList()..sort();
      await prefs.setStringList(_includeKey, sorted);
    }

    if (excludeClean.isEmpty) {
      await prefs.remove(_excludeKey);
    } else {
      final sorted = excludeClean.toList()..sort();
      await prefs.setStringList(_excludeKey, sorted);
    }
  }

  static bool isAllowedPath(
    String path,
    Set<String>? includedPrefixes,
    Set<String> excludedPrefixes,
  ) {
    final p = path.trim();
    if (p.isEmpty) return false;
    for (final ex in excludedPrefixes) {
      if (ex.isEmpty) continue;
      if (p == ex) return false;
      if (p.startsWith('$ex/')) return false;
    }
    if (includedPrefixes == null) return true;
    for (final inc in includedPrefixes) {
      if (inc.isEmpty) continue;
      if (p == inc) return true;
      if (p.startsWith('$inc/')) return true;
    }
    return false;
  }
}


