// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Represents a repository entry provided by a Git platform.
///
/// Contains the repository [name] and a [cloneUrl] that can be used
/// for cloning (e.g. HTTPS or SSH URL).
class Repository {
  /// Creates a repository description with [name] and [cloneUrl].
  const Repository({
    required this.name,
    required this.cloneUrl,
  });

  /// The repository name.
  final String name;

  /// The clone URL (HTTPS or SSH).
  final String cloneUrl;
}
