// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

/// Utility class to manage .gg_multi_status files in repo directories.
class StatusUtils {
  /// Status Unlocalized
  static const String statusUnlocalized = 'unlocalized';

  /// Status Localized
  static const String statusLocalized = 'localized';

  /// Status Git Unlocalized
  static const String statusGitLocalized = 'git-localized';

  /// Status Local Merged
  static const String statusLocalMerged = 'local-merged';

  /// Status Merged
  static const String statusMerged = 'merged';

  /// Sets the status in the .gg_multi_status file inside [repoDir].
  /// Logs success in green or error in red, but does not throw on error.
  static void setStatus(
    Directory repoDir,
    String status, {
    required GgLog ggLog,
  }) {
    final statusFile = File(path.join(repoDir.path, '.gg_multi_status'));
    try {
      statusFile.writeAsStringSync(jsonEncode({'status': status}));
    } catch (e) {
      ggLog(red('Failed to set status in ${repoDir.path}: $e'));
    }
  }

  /// Reads the status from the .gg_multi_status file inside [repoDir].
  /// Returns the status string if successful, or null on failure.
  /// Logs errors in red.
  static String? readStatus(
    Directory repoDir, {
    required GgLog ggLog,
  }) {
    final statusFile = File(path.join(repoDir.path, '.gg_multi_status'));
    if (!statusFile.existsSync()) {
      ggLog(red('Missing .gg_multi_status file in ${repoDir.path}'));
      return null;
    }
    try {
      final content = statusFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data['status'] as String?;
    } catch (e) {
      ggLog(red('Failed to read status from ${repoDir.path}: $e'));
      return null;
    }
  }
}
