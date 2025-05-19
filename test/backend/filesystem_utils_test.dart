// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:kidney_core/src/backend/filesystem_utils.dart';

void main() {
  group(
    'copyDirectory',
    () {
      late Directory sourceDir;
      late Directory destinationDir;

      setUp(() async {
        // Create a temporary source directory for every test.
        sourceDir = await Directory.systemTemp.createTemp('copy_test_src_');

        // Create an empty destination directory path and remove the folder so
        // that copyDirectory needs to create it.
        destinationDir =
            await Directory.systemTemp.createTemp('copy_test_dst_');
        await destinationDir.delete(recursive: true);
      });

      tearDown(() async {
        // Clean up any leftover directories.
        if (sourceDir.existsSync()) {
          await sourceDir.delete(recursive: true);
        }
        if (destinationDir.existsSync()) {
          await destinationDir.delete(recursive: true);
        }
      });

      test(
        'copies files and sub-directories',
        () async {
          // Arrange – create some files and a nested folder.
          final nestedDir = Directory(path.join(sourceDir.path, 'nested'));
          await nestedDir.create(recursive: true);

          final rootFile = File(path.join(sourceDir.path, 'root.txt'));
          await rootFile.writeAsString('root file');

          final nestedFile = File(path.join(nestedDir.path, 'nested.txt'));
          await nestedFile.writeAsString('nested file');

          // Act.
          await copyDirectory(sourceDir, destinationDir);

          // Assert – both files must exist with their original content.
          final copiedRootFile =
              File(path.join(destinationDir.path, 'root.txt'));
          final copiedNestedFile =
              File(path.join(destinationDir.path, 'nested', 'nested.txt'));

          expect(copiedRootFile.existsSync(), isTrue);
          expect(copiedNestedFile.existsSync(), isTrue);
          expect(copiedRootFile.readAsStringSync(), 'root file');
          expect(copiedNestedFile.readAsStringSync(), 'nested file');
        },
      );

      test(
        'throws ArgumentError when source does not exist',
        () async {
          final nonExisting = Directory(
            path.join(
              Directory.systemTemp.path,
              'does_not_exist_${DateTime.now().microsecondsSinceEpoch}',
            ),
          );

          expect(
            () => copyDirectory(nonExisting, destinationDir),
            throwsA(isA<ArgumentError>()),
          );
        },
      );
    },
  );
}
