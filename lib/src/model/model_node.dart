// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:meta/meta.dart';

/// Stripped down information derived from [AstNode] containing only information
/// needed to resurrect the source code of [element].
class ModelNode {
  final Element _element;
  final AnalysisContext _analysisContext;

  factory ModelNode(
      AstNode? sourceNode, Element element, AnalysisContext analysisContext) {
    if (sourceNode == null) {
      return ModelNode._(element, analysisContext);
    } else {
      // Get a node higher up the syntax tree that includes the semicolon.
      // In this case, it is either a [FieldDeclaration] or
      // [TopLevelVariableDeclaration]. (#2401)
      if (sourceNode is VariableDeclaration) {
        sourceNode = sourceNode.parent!.parent!;
        assert(sourceNode is FieldDeclaration ||
            sourceNode is TopLevelVariableDeclaration);
      }
      return ModelNode._(element, analysisContext);
    }
  }

  ModelNode._(this._element, this._analysisContext);
}

@visibleForTesting
extension SourceStringExtensions on String {
  String substringFromLineStart(int offset, int endOffset) {
    var lineStartOffset = startOfLineWithOffset(offset);
    return substring(lineStartOffset, endOffset);
  }

  // Finds the start of the line which contains the character at [offset].
  int startOfLineWithOffset(int offset) {
    var i = offset;
    // Walk backwards until we find the previous line's EOL character.
    while (i > 0) {
      i -= 1;
      if (this[i] == '\n' || this[i] == '\r') {
        i += 1;
        break;
      }
    }
    return i;
  }

  /// Strips leading doc comments from the given source code.
  String get stripDocComments {
    var remainder = trimLeft();
    var lineComments = remainder.startsWith(_tripleSlash) ||
        remainder.startsWith(_escapedTripleSlash);
    var blockComments = remainder.startsWith(_slashStarStar) ||
        remainder.startsWith(_escapedSlashStarStar);

    return split('\n').where((String line) {
      if (lineComments) {
        if (line.startsWith(_tripleSlash) ||
            line.startsWith(_escapedTripleSlash)) {
          return false;
        }
        lineComments = false;
        return true;
      } else if (blockComments) {
        if (line.contains(_starSlash) || line.contains(_escapedStarSlash)) {
          blockComments = false;
          return false;
        }
        if (line.startsWith(_slashStarStar) ||
            line.startsWith(_escapedSlashStarStar)) {
          return false;
        }
        return false;
      }

      return true;
    }).join('\n');
  }

  /// Strips the common indent from the given source fragment.
  String get stripIndent {
    var remainder = trimLeft();
    var indent = substring(0, length - remainder.length);
    return split('\n').map((line) {
      line = line.trimRight();
      return line.startsWith(indent) ? line.substring(indent.length) : line;
    }).join('\n');
  }
}

const HtmlEscape _escape = HtmlEscape();

const String _tripleSlash = '///';

final String _escapedTripleSlash = _escape.convert(_tripleSlash);

const String _slashStarStar = '/**';

final String _escapedSlashStarStar = _escape.convert(_slashStarStar);

const String _starSlash = '*/';

final String _escapedStarSlash = _escape.convert(_starSlash);
