// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dartdoc/src/model/documentation_comment.dart';
import 'package:dartdoc/src/model/library.dart';
import 'package:dartdoc/src/warnings.dart';

final _canonicalRegExp = RegExp(r'{@(canonicalFor|canonical-for)\s([^}]+)}');

/// Used by [Library] to implement the `canonicalFor` directive.
mixin CanonicalFor on DocumentationComment {
  Set<String>? _canonicalFor;

  Set<String> get canonicalFor {
    if (_canonicalFor == null) {
      buildDocumentationAddition(documentationComment);
    }
    return _canonicalFor!;
  }

  /// Hides `canonicalFor` from doc while leaving a note to ourselves to
  /// help with ambiguous canonicalization determination.
  ///
  /// Example:
  ///
  ///     {@canonicalFor libname.ClassName}
  @override
  String buildDocumentationAddition(String rawDocs) {
    rawDocs = super.buildDocumentationAddition(rawDocs);
    var newCanonicalFor = <String>{};
    rawDocs = rawDocs.replaceAllMapped(_canonicalRegExp, (Match match) {
      var canonicalName = match.group(1)!;
      if (canonicalName == 'canonicalFor') {
        warn(PackageWarning.deprecated,
            message: "Deprecated form of @canonical-for tag, '@canonicalFor'. "
                "Tag is now written '@canonical-for'.");
      }
      var elementName = match.group(2)!;
      newCanonicalFor.add(elementName);
      return '';
    });

    _canonicalFor = newCanonicalFor;
    return rawDocs;
  }
}
