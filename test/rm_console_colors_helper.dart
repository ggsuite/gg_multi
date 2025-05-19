// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Removes all ANSI escape sequences that set console colors from [str].
String rmConsoleColors(Object str) {
  final ansiColorExpr = RegExp(r'\x1B\[[0-9;]*m');

  return str.toString().replaceAll(ansiColorExpr, '');
}
