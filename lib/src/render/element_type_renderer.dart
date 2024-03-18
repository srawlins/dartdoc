// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dartdoc/src/element_type.dart';
import 'package:dartdoc/src/render/parameter_renderer.dart';
import 'package:dartdoc/src/render/record_type_field_renderer.dart';
import 'package:dartdoc/src/render/rendered_text.dart';

abstract class ElementTypeRenderer<T extends ElementType> {
  const ElementTypeRenderer();

  String renderLinkedName(T elementType);

  RenderBuffer renderedName(T elementType);

  String renderNameWithGenerics(T elementType, {bool plain = false}) => '';

  RenderBuffer renderedNameWithGenerics(T elementType);

  String wrapNullabilityParens(T elementType, String inner) =>
      elementType.nullabilitySuffix.isEmpty
          ? inner
          : '$inner${elementType.nullabilitySuffix}';
}

// HTML implementations.

abstract class ElementTypeRendererHtml<T extends ElementType>
    extends ElementTypeRenderer<T> {
  const ElementTypeRendererHtml();

  RenderBuffer _renderedName(
      T elementType, String name, Iterable<ElementType> typeArguments) {
    var buffer = RenderBuffer()..writeText(name);
    if (typeArguments.isNotEmpty &&
        !typeArguments.every((t) => t.name == 'dynamic')) {
      var htmlBuffer = StringBuffer()
        ..write('<span class="signature">')
        ..write('&lt;<wbr><span class="type-parameter">')
        ..writeAll(typeArguments.map((t) => t.linkedName),
            '</span>, <span class="type-parameter">')
        ..write('</span>&gt;')
        ..write('</span>');
      buffer.writeHtml(
        htmlBuffer.toString(),
        // TODO: not linkedName!
        '<${typeArguments.map((t) => t.linkedName).join(', ')}>',
      );
    }
    return buffer..writeText(elementType.nullabilitySuffix);
  }

  String _renderNameWithGenerics(
      T elementType, String name, Iterable<ElementType> typeArguments,
      {bool plain = false}) {
    var buffer = StringBuffer()..write(name);
    if (typeArguments.isNotEmpty &&
        !typeArguments.every((t) => t.name == 'dynamic')) {
      if (plain) {
        buffer
          ..write('<')
          ..writeAll(typeArguments.map((t) => t.nameWithGenericsPlain), ', ')
          ..write('>');
      } else {
        buffer
          ..write('&lt;<wbr><span class="type-parameter">')
          ..writeAll(typeArguments.map((t) => t.nameWithGenerics),
              '</span>, <span class="type-parameter">')
          ..write('</span>&gt;');
      }
    }
    buffer.write(elementType.nullabilitySuffix);
    return buffer.toString();
  }

  RenderBuffer _renderedNameWithGenerics(
      T elementType, String name, Iterable<ElementType> typeArguments) {
    var buffer = RenderBuffer()..writeText(name);
    if (typeArguments.isNotEmpty &&
        !typeArguments.every((t) => t.name == 'dynamic')) {
      var htmlBuffer = StringBuffer()
        ..write('&lt;<wbr><span class="type-parameter">')
        ..writeAll(typeArguments.map((t) => t.nameWithGenerics),
            '</span>, <span class="type-parameter">')
        ..write('</span>&gt;');
      buffer.writeHtml(
        htmlBuffer.toString(),
        // Grr nameWithGenerics
        '<${typeArguments.map((t) => t.nameWithGenerics).join(', ')}>',
      );
    }
    buffer.writeText(elementType.nullabilitySuffix);
    return buffer;
  }
}

class FunctionTypeElementTypeRendererHtml
    extends ElementTypeRenderer<FunctionTypeElementType> {
  const FunctionTypeElementTypeRendererHtml();

  @override
  String renderLinkedName(FunctionTypeElementType elementType) {
    var buffer = StringBuffer()
      ..write(elementType.returnType.linkedName)
      ..write(' ')
      ..write(elementType.nameWithGenerics)
      ..write('<span class="signature">(')
      ..write(const ParameterRendererHtml()
          .renderLinkedParams(elementType.parameters))
      ..write(')</span>');
    return wrapNullabilityParens(elementType, buffer.toString());
  }

  @override
  RenderBuffer renderedName(FunctionTypeElementType elementType) {
    var nameWithGenerics = elementType.nameWithGenerics;
    var parameters = const ParameterRendererHtml()
        .renderLinkedParams(elementType.parameters);

    return RenderBuffer()
      ..writeRenderBuffer(elementType.returnType.renderedName)
      ..writeText(' ')
      ..writeHtml(nameWithGenerics, nameWithGenerics)
      ..writeHtml('<span class="signature">(', '(')
      ..writeHtml(parameters, parameters)
      ..writeHtml(')</span>', ')');

    //return wrapNullabilityParens(elementType, buffer.toString());
  }

  @override
  String renderNameWithGenerics(FunctionTypeElementType elementType,
      {bool plain = false}) {
    var buffer = StringBuffer()..write(elementType.name);
    if (elementType.typeFormals.isNotEmpty) {
      if (!elementType.typeFormals.every((t) => t.name == 'dynamic')) {
        if (plain) {
          buffer
            ..write('<')
            ..writeAll(elementType.typeFormals.map((t) => t.name), ', ')
            ..write('>');
        } else {
          buffer
            ..write('&lt;<wbr><span class="type-parameter">')
            ..writeAll(elementType.typeFormals.map((t) => t.name),
                '</span>, <span class="type-parameter">')
            ..write('</span>&gt;');
        }
      }
    }
    return buffer.toString();
  }

  @override
  RenderBuffer renderedNameWithGenerics(FunctionTypeElementType elementType) {
    var buffer = RenderBuffer()..writeText(elementType.name);
    if (elementType.typeFormals.isNotEmpty) {
      if (!elementType.typeFormals.every((t) => t.name == 'dynamic')) {
        var htmlBuffer = StringBuffer()
          ..write('&lt;<wbr><span class="type-parameter">')
          ..writeAll(elementType.typeFormals.map((t) => t.name),
              '</span>, <span class="type-parameter">')
          ..write('</span>&gt;');
        buffer.writeHtml(
          htmlBuffer.toString(),
          '<${elementType.typeFormals.map((t) => t.name).join(', ')}>',
        );
      }
    }
    return buffer;
  }
}

class ParameterizedElementTypeRendererHtml
    extends ElementTypeRendererHtml<ParameterizedElementType> {
  const ParameterizedElementTypeRendererHtml();

  @override
  String renderLinkedName(ParameterizedElementType elementType) =>
      _renderedName(
        elementType,
        elementType.modelElement.linkedName,
        elementType.typeArguments,
      ).toString();

  @override
  RenderBuffer renderedName(ParameterizedElementType elementType) =>
      _renderedName(
        elementType,
        elementType.modelElement.linkedName,
        elementType.typeArguments,
      );

  @override
  String renderNameWithGenerics(ParameterizedElementType elementType,
          {bool plain = false}) =>
      _renderNameWithGenerics(
        elementType,
        elementType.modelElement.name,
        elementType.typeArguments,
        plain: plain,
      );

  @override
  RenderBuffer renderedNameWithGenerics(ParameterizedElementType elementType) =>
      _renderedNameWithGenerics(
        elementType,
        elementType.modelElement.name,
        elementType.typeArguments,
      );
}

class RecordElementTypeRendererHtml
    extends ElementTypeRendererHtml<RecordElementType> {
  const RecordElementTypeRendererHtml();

  @override
  String renderLinkedName(RecordElementType elementType) =>
      renderedName.toString();

  @override
  RenderBuffer renderedName(RecordElementType elementType) {
    var renderedFields =
        const RecordTypeFieldListHtmlRenderer().renderLinkedFields(elementType);
    renderedFields = RenderBuffer()
      ..writeHtml(renderedFields.toString().trim(), renderedFields.text.trim());
    var buffer = RenderBuffer()
      ..writeText('(')
      ..writeRenderBuffer(renderedFields)
      ..writeText(')');
    if (elementType.nullabilitySuffix.isNotEmpty) {
      buffer.writeText(elementType.nullabilitySuffix);
    }
    return buffer;
  }

  @override
  String renderNameWithGenerics(RecordElementType elementType,
      {bool plain = false}) {
    return '${elementType.name}${elementType.nullabilitySuffix}';
  }

  @override
  RenderBuffer renderedNameWithGenerics(RecordElementType elementType) {
    return RenderBuffer()
      ..writeText('${elementType.name}${elementType.nullabilitySuffix}');
  }
}

class AliasedUndefinedElementTypeRendererHtml
    extends ElementTypeRendererHtml<AliasedUndefinedElementType> {
  const AliasedUndefinedElementTypeRendererHtml();

  @override
  String renderLinkedName(AliasedUndefinedElementType elementType) =>
      _renderedName(
        elementType,
        elementType.aliasElement.linkedName,
        elementType.aliasArguments,
      ).toString();

  @override
  RenderBuffer renderedName(AliasedUndefinedElementType elementType) =>
      _renderedName(
        elementType,
        elementType.aliasElement.linkedName,
        elementType.aliasArguments,
      );

  @override
  String renderNameWithGenerics(AliasedUndefinedElementType elementType,
          {bool plain = false}) =>
      _renderNameWithGenerics(
        elementType,
        elementType.aliasElement.name,
        elementType.aliasArguments,
        plain: plain,
      );

  @override
  RenderBuffer renderedNameWithGenerics(
          AliasedUndefinedElementType elementType) =>
      _renderedNameWithGenerics(
        elementType,
        elementType.aliasElement.name,
        elementType.aliasArguments,
      );
}

class AliasedElementTypeRendererHtml
    extends ElementTypeRendererHtml<AliasedElementType> {
  const AliasedElementTypeRendererHtml();

  @override
  String renderLinkedName(AliasedElementType elementType) => _renderedName(
        elementType,
        elementType.aliasElement.linkedName,
        elementType.aliasArguments,
      ).toString();

  @override
  RenderBuffer renderedName(AliasedElementType elementType) => _renderedName(
        elementType,
        elementType.aliasElement.linkedName,
        elementType.aliasArguments,
      );

  @override
  String renderNameWithGenerics(AliasedElementType elementType,
          {bool plain = false}) =>
      _renderNameWithGenerics(
        elementType,
        elementType.aliasElement.name,
        elementType.aliasArguments,
        plain: plain,
      );

  @override
  RenderBuffer renderedNameWithGenerics(AliasedElementType elementType) =>
      _renderedNameWithGenerics(
        elementType,
        elementType.aliasElement.name,
        elementType.aliasArguments,
      );
}
