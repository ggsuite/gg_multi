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

/// Utility class to manage .kidney_status files in repo directories.
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

  /// Sets the status in the .kidney_status file inside [repoDir].
  /// Logs success in green or error in red, but does not throw on error.
  static void setStatus(
    Directory repoDir,
    String status, {
    required GgLog ggLog,
  }) {
    final statusFile = File(path.join(repoDir.path, '.kidney_status'));
    try {
      statusFile.writeAsStringSync(jsonEncode({'status': status}));
    } catch (e) {
      ggLog(red('Failed to set status in ${repoDir.path}: $e'));
    }
  }
}
