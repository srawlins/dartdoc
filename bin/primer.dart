// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dartdoc.primer;

import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:dartdoc/dartdoc.dart';
import 'package:dartdoc/src/generator_primer.dart';
import 'package:dartdoc/src/package_meta.dart';

main(List<String> args) {
  final Directory inputDir =
      args.isEmpty ? Directory.current : new Directory(args.first);
  final Directory outputDir = new Directory(defaultOutDir);

  print("Generating into ${outputDir.path}${Platform.pathSeparator}.");
  print('');

  List generators = [new PrimerGenerator()];

  DartDoc dartdoc = new DartDoc(inputDir, [], getSdkDir(), generators,
      outputDir, null, new PackageMeta.fromDir(inputDir));
  dartdoc.generateDocs();
}
