// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

/*class RenderedText {
  final String html;
  final String text;

  RenderedText._(this.html, this.text);

  RenderedText.plainText(this.text) : html = text;
}*/

class RenderBuffer {
  final StringBuffer _htmlBuffer = StringBuffer();
  final StringBuffer _textBuffer = StringBuffer();

  RenderBuffer();

  RenderBuffer.plainText(String text) {
    _htmlBuffer.write(text);
    _textBuffer.write(text);
  }

  void writeText(String text) {
    _htmlBuffer.write(text);
    _textBuffer.write(text);
  }

  void writeEscapedText(String text) {
    _htmlBuffer.write(const HtmlEscape().convert(text));
    _textBuffer.write(text);
  }

  void writeHtml(String html, String text) {
    _htmlBuffer.write(html);
    _textBuffer.write(text);
  }

  void writeRenderBuffer(RenderBuffer renderedText) {
    _htmlBuffer.write(renderedText.toString());
    _textBuffer.write(renderedText.text);
  }

  @override
  String toString() => _htmlBuffer.toString();

  String get text => _textBuffer.toString();
}
