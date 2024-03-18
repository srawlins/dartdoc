// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart';
import 'package:dartdoc/src/element_type.dart';
import 'package:dartdoc/src/render/rendered_text.dart';

/// Render HTML suitable for a single, wrapped line.
class RecordTypeFieldListHtmlRenderer extends _RecordTypeFieldListRenderer {
  const RecordTypeFieldListHtmlRenderer();

  @override
  String orderedList(String listItems) => listItems;

  @override
  RenderBuffer annotation(String name) =>
      RenderBuffer()..writeHtml('<span>$name</span>', name);

  @override
  RenderBuffer field(RenderBuffer name) => RenderBuffer()
    ..writeHtml(
      '<span class="field">${name.toString()}</span>',
      name.text,
    );

  @override
  RenderBuffer fieldName(String name) =>
      RenderBuffer()..writeHtml('<span class="field-name">$name</span>', name);

  @override
  RenderBuffer typeName(String name) => RenderBuffer()
    ..writeHtml('<span class="type-annotation">$name</span>', name);
}

abstract class _RecordTypeFieldListRenderer {
  const _RecordTypeFieldListRenderer();

  String orderedList(String listItems);
  RenderBuffer annotation(String name);
  RenderBuffer field(RenderBuffer name);
  RenderBuffer fieldName(String name);
  RenderBuffer typeName(String name);

  RenderBuffer renderLinkedFields(RecordElementType recordElementType) {
    final buffer = RenderBuffer();

    void renderLinkedFieldSublist(
      List<RecordTypeField> fields, {
      required bool trailingComma,
      String openBracket = '',
      String closeBracket = '',
    }) {
      fields.forEachIndexed((index, field) {
        var prefix = '';
        var suffix = '';
        if (identical(field, fields.first)) {
          prefix = openBracket;
        }
        if (identical(field, fields.last)) {
          suffix += closeBracket;
          if (trailingComma) suffix += ', ';
        } else {
          suffix += ', ';
        }

        var fieldBuffer = RenderBuffer();
        fieldBuffer.writeText(prefix);
        var modelType =
            recordElementType.getTypeFor(field.type, recordElementType.library);
        var renderedTypeName = typeName(modelType.linkedName);
        if (renderedTypeName.toString().isNotEmpty) {
          fieldBuffer.writeRenderBuffer(renderedTypeName);
        }
        if (field is RecordTypeNamedField) {
          fieldBuffer.writeText(' ');
          fieldBuffer.writeRenderBuffer(fieldName(field.name));
        }
        fieldBuffer.writeText(suffix);
        buffer.writeRenderBuffer(this.field(fieldBuffer));
      });
    }

    if (recordElementType.positionalFields.isNotEmpty) {
      renderLinkedFieldSublist(
        recordElementType.positionalFields,
        trailingComma: recordElementType.namedFields.isNotEmpty,
      );
    }
    if (recordElementType.namedFields.isNotEmpty) {
      renderLinkedFieldSublist(
        recordElementType.namedFields,
        trailingComma: false,
        openBracket: '{',
        closeBracket: '}',
      );
    }
    return buffer;
  }
}
