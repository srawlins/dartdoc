// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dartdoc.generator_primer;

import 'dart:io';

import 'dart:async' show Future;

import 'package:analyzer/src/generated/element.dart';
import 'package:markdown/markdown.dart';
import 'package:path/path.dart' as path;

import 'model.dart';
import 'package_meta.dart';
import '../generator.dart';

class PrimerGenerator extends Generator {
  Future generate(Package package, Directory out) {
    if (!out.existsSync()) out.createSync();

    new _Primer(package, out).generate();

    return new Future.value();
  }
}

class _Primer {
  final Package package;
  final Directory out;

  _Primer(this.package, this.out);

  void generate() {
    _page(new IndexPage(package));

    if (package.packageMeta.getLicenseContents() != null) {
      _page(new LicensePage(package));
    }

    if (package.packageMeta.getChangelogContents() != null) {
      _page(new ChangelogPage(package));
    }

    for (Library library in package.libraries) {
      _page(new LibraryPage(library));

      library.enums.forEach((Class clazz) => _page(new ClassPage(clazz)));
      library.classes.forEach((Class clazz) => _page(new ClassPage(clazz)));
      library.exceptions.forEach((Class clazz) => _page(new ClassPage(clazz)));
    }
  }

  void _page(Page page) {
    File f = new File(path.join(out.path, page.ref));
    f.writeAsStringSync(page.create());
  }
}

abstract class Page extends _HtmlPrinter {
  final Package package;

  Page(this.package);

  String get subTitle;
  String get ref;

  String get pageTitle =>
      package.name; //package.isSdk ? package.name : "Package ${package.name}";

  String create() {
    reset();

    start(title: pageTitle,
        // TODO: hmm
        theme: 'http://primercss.io/docs.css', inlineStyle: extraCss);
//      theme: 'https://cdn.jsdelivr.net/primer/2.1.0/primer.css',
//      inlineStyle: css);

    header();
    startTag('div', classes: "container");
    startTag('div', classes: "columns docs-layout");

    startTag('div', classes: "column one-fourth");
    nav();
    endTag(); // div.column.one-fourth

    startTag('div', classes: "column three-fourths markdown-body");
    subtitle();
    contents();
    endTag(); // div.column.one-fourths.markdown-body

    endTag(); // div.columns.docs-layout
    footer();
    endTag(); // div.container
    end();

    return toString();
  }

  void header() {
    startTag('header', classes: "masthead");
    startTag('div', classes: "container");
    title();
    startTag('nav', classes: "masthead-nav");
    tag("a", href: "index.html", contents: "Docs");
    if (package.packageMeta.getChangelogContents() != null) {
      tag("a", href: "changelog.html", contents: "Changelog");
    }
    if (package.packageMeta.getLicenseContents() != null) {
      tag("a", href: "license.html", contents: "License");
    }
    if (package.packageMeta.homepage != null) {
      tag("a", href: package.packageMeta.homepage, contents: "Source");
    }
    endTag(); // nav.masthead-nav
    endTag(); // div.container
    endTag(); // header
  }

  void title() {
    tag("a", classes: "masthead-logo", contents: pageTitle);
  }

  void subtitle() {
    tag("h1", contents: subTitle, classes: "page-title");
  }

  void contents();

  void nav();

  void footer() {
    startTag('footer', classes: "footer");
    writeln("Convenient footer here.");
    endTag();
  }

  void navItems(String category, List<ModelElement> elements) {
    if (elements.isEmpty) return;
    tag("span", classes: "menu-heading", contents: category);
    for (ModelElement element in elements) {
      tag("a",
          classes: "menu-item${_deprecated(element)}",
          contents: _label(element),
          href: "${_ref(element)}");
    }
  }

  void contentItems(String category, List<ModelElement> elements) {
    if (elements.isEmpty) return;

    tag("h2", contents: category);
    elements.forEach(contentItem);
  }

  void contentItem(ModelElement element) {
    contentHeader(element);
    contentBody(element);
  }

  void contentHeader(ModelElement element) {
    tag("a", attributes: 'name="${element.name}"');
    tag("h3", contents: _label(element), classes: _deprecated(element));

//    startTag("pre");
//    if (element.hasAnnotations) {
//      //element.annotations.forEach((a) {
//      //  tag("div", classes: "small", contents: "@${a}");
//      //});
//      writeln(element.annotations.map((a) => "@${a}").join("<br>") + "<br>");
//    }
//    writeln(_label(element));
//    endTag();
  }

  void contentBody(ModelElement element) {
    if (element.hasDocumentation) {
      tag("p", contents: _markdown(element.documentation));
    }
  }

  String _ref(ModelElement element) {
    String base =
        (element.library.element as LibraryElement).definingCompilationUnit.name;
    if (base.endsWith('.dart')) base = base.substring(0, base.length - 5);

    if (element is Library) return "${base}.html";

    String id = element.name;

    if (element is Field || element is Method || element is Constructor) {
      // TODO: We should have a more reliable way to do this.
      String classId = element.element.enclosingElement.name;
      return "${base}_${classId}.html#${id}";
    } else if (element is Class) {
      return "${base}_${id}.html";
    } else {
      return "${base}.html#${id}";
    }
  }

  String _label(ModelElement element) {
    if (element is Library) {
      return (element.element as LibraryElement).definingCompilationUnit.name;
    } else if (element is Operator) {
      return element.name;
    } else if (element is Method ||
        element is Constructor ||
        element is ModelFunction) {
      return element.name + "()";
    } else {
      return element.name;
    }
  }

  String _summary(element) {
    if (element is Package) {
      return package.packageMeta.description;
    } else {
      if (!element.hasDocumentation) return null;
      String docs = element.documentation;
      return docs
          .split('\n')
          .map((l) => l.trimRight())
          .takeWhile((l) => l.isNotEmpty)
          .join(' ');
    }
  }

  String _markdown(String text) {
    // TODO: Use the markdown processing code from html_generator.dart.
    return markdownToHtml(text);
  }

  String _deprecated(ModelElement element) =>
      element.isDeprecated ? ' deprecated' : '';
}

abstract class NonSelectedPage extends Page {
  final String subTitle;
  final String ref;

  NonSelectedPage(Package package, this.subTitle, this.ref) : super(package);

  void nav() {
    startTag("nav", classes: "menu docs-menu");
    navItems("Libraries", package.libraries);
    endTag(); // nav
  }
}

class IndexPage extends NonSelectedPage {
  IndexPage(Package package) : super(package, package.name, 'index.html');

  void contents() {
    tag("p", classes: "lead", contents: _markdown(_summary(package)));

    for (Library library in package.libraries) {
      tag("h2", contents: _label(library));
      tag("p", contents: _librarySummary(library));
    }
  }

  String _librarySummary(Library library) {
    if (library.hasDocumentation) {
      return _markdown(_summary(library));
    } else {
      return "<em>No documentation available.</em>";
    }
  }
}

class LicensePage extends NonSelectedPage {
  LicensePage(Package package) : super(package, 'License', 'license.html');

  void contents() {
    FileContents license = package.packageMeta.getLicenseContents();
    // TODO: handle plain text
    writeln(_markdown(license.contents));
  }
}

class ChangelogPage extends NonSelectedPage {
  ChangelogPage(Package package)
      : super(package, 'Changelog', 'changelog.html');

  void subtitle() {
    // Do nothing; changelog's often include titles.
  }

  void contents() {
    FileContents changelog = package.packageMeta.getChangelogContents();
    // TODO: handle plain text
    writeln(_markdown(changelog.contents));
  }
}

class LibraryPage extends Page {
  final Library library;

  LibraryPage(Library library)
      : this.library = library,
        super(library.package);

  String get subTitle => _label(library);
  String get ref => _ref(library);

  void title() {
    tag("a", contents: pageTitle, classes: "masthead-logo", href: "index.html");
    tag("a", classes: "masthead-logo", contents: " &nbsp;&gt;&nbsp; ");
    tag("a", classes: "masthead-logo", contents: subTitle);
  }

  void nav() {
    startTag("nav", classes: "menu docs-menu");
    navItems("Constants", library.constants);
    navItems("Properties", library.properties);
    navItems("Functions", library.functions);
    navItems("Typedefs", library.typedefs);
    navItems("Enums", library.enums);
    navItems("Classes", library.classes);
    navItems("Exceptions", library.exceptions);
    endTag(); // nav
  }

  void contents() {
    if (library.hasDocumentation) {
      tag("p", contents: _markdown(library.documentation));
    }

    contentItems("Constants", library.constants);
    contentItems("Properties", library.properties);
    contentItems("Functions", library.functions);
    contentItems("Typedefs", library.typedefs);
    contentItems("Enums", library.enums);
    contentItems("Classes", library.classes);
    contentItems("Exceptions", library.exceptions);
  }

  void contentBody(ModelElement element) {
    if (element.hasDocumentation && element is Class) {
      tag("p", contents: _markdown(_summary(element)));
    } else {
      super.contentBody(element);
    }
  }
}

class ClassPage extends Page {
  final Class clazz;

  ClassPage(Class clazz)
      : this.clazz = clazz,
        super(clazz.package);

  String get subTitle => _label(clazz);

  String get ref => _ref(clazz);

  void title() {
    tag("a", contents: pageTitle, classes: "masthead-logo", href: "index.html");
    tag("a", classes: "masthead-logo", contents: " &nbsp;&gt;&nbsp; ");
    tag("a", classes: "masthead-logo", contents: _label(clazz.library));
    tag("a",
        classes: "masthead-logo",
        contents: " &nbsp;&gt;&nbsp; ",
        href: "${_ref(clazz.library)}");
    tag("a", classes: "masthead-logo", contents: subTitle);
  }

  void nav() {
    startTag("nav", classes: "menu docs-menu");

    navItems("Constants", clazz.constants);
    navItems("Static Properties", clazz.staticProperties);
    navItems("Static Methods", clazz.staticMethods);
    navItems("Constructors", clazz.constructors);
    navItems("Properties", clazz.instanceProperties);
    navItems("Operators", clazz.operators);
    navItems("Methods", clazz.instanceMethods);

    endTag(); // nav
  }

  void contents() {
    if (clazz.hasDocumentation) {
      tag("p", contents: _markdown(clazz.documentation));
    }

    contentItems("Constants", clazz.constants);
    contentItems("Static Properties", clazz.staticProperties);
    contentItems("Static Methods", clazz.staticMethods);
    contentItems("Constructors", clazz.constructors);
    contentItems("Properties", clazz.instanceProperties);
    contentItems("Operators", clazz.operators);
    contentItems("Methods", clazz.instanceMethods);
  }
}

class _HtmlPrinter {
  final StringBuffer _buffer = new StringBuffer();
  bool _startOfLine = true;
  final List<String> _tags = [];
  final List<bool> _indents = [];
  String _indent = '';

  _HtmlPrinter() {
    _init();
  }

  void _init() {
    writeln('<!DOCTYPE html>');
    writeln();
    writeln('<!-- generated by dartdoc -->');
    writeln();
  }

  void start({String title, String cssRef, String theme, String jsScript,
      String inlineStyle}) {
    startTag('html', newLine: false);
    writeln();
    startTag('head');
    writeln('<meta charset="utf-8">');
    writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    if (title != null) {
      writeln('<title>${title}</title>');
    }
    if (cssRef != null) {
      writeln('<link href="${cssRef}" rel="stylesheet" media="screen">');
    }
    if (theme != null) {
      writeln('<link href="${theme}" rel="stylesheet">');
    }
    if (jsScript != null) {
      writeln('<script src="${jsScript}"></script>');
    }
    if (inlineStyle != null) {
      startTag('style');
      writeln(inlineStyle);
      endTag();
    }
    endTag();
    writeln();
    startTag('body', newLine: false);
    writeln();
  }

  void startTag(String tag,
      {String attributes, String classes, bool newLine: true}) {
    if (classes != null && classes.isNotEmpty) {
      if (attributes == null) {
        attributes = 'class="${classes}"';
      } else {
        attributes += ' class="${classes}"';
      }
    }

    if (attributes != null) {
      if (newLine) {
        writeln('<${tag} ${attributes}>');
      } else {
        write('<${tag} ${attributes}>');
      }
    } else {
      if (newLine) {
        writeln('<${tag}>');
      } else {
        write('<${tag}>');
      }
    }
    _indents.add(newLine);
    if (newLine) {
      _indent = '$_indent\t';
    }
    _tags.add(tag);
  }

  void tag(String tag,
      {String contents, String classes, String href, String attributes}) {
    if (attributes == null) attributes = '';
    if (contents == null) contents = '';

    if (classes != null && classes.isNotEmpty) attributes +=
        ' class="${classes}"';
    if (href != null) attributes += ' href="${href}"';

    if (attributes.isNotEmpty) attributes = ' ' + attributes.trim();

    writeln('<$tag$attributes>$contents</$tag>');
  }

  void endTag() {
    String tag = _tags.removeLast();
    bool wasIndent = _indents.removeLast();
    if (wasIndent) {
      _indent = _indent.substring(0, _indent.length - 1);
    }
    writeln('</${tag}>');
  }

  void end() {
    // body
    endTag();
    // html
    endTag();
  }

  String toString() => _buffer.toString();

  void reset() {
    _buffer.clear();
    _startOfLine = true;
    _tags.clear();
    _indents.clear();
    _indent = '';

    _init();
  }

  void write(String str) {
    if (_startOfLine) {
      _buffer.write(_indent);
      _startOfLine = false;
    }
    _buffer.write(str);
  }

  void writeln([String str]) {
    if (str == null) {
      write('\n');
    } else {
      write('${str}\n');
    }
    _startOfLine = true;
  }
}

final String css = '''
/*
 * Primer documentation styles
 * http://primercss.io
 *
 * Released under MIT license. Copyright 2015 GitHub, Inc.
 */
html {
  font-size: 16px;
}

body {
  font-family: "Helvetica Neue", Helvetica, arial, nimbussansl, liberationsans, freesans, clean, sans-serif, "Segoe UI Emoji", "Segoe UI Symbol";
  font-size: 1rem;
}

.container {
  width: auto;
  max-width: 1020px;
  padding-left: 20px;
  padding-right: 20px;
}

.markdown-body {
  overflow: visible;
}

.btn-reverse {
  color: #fff;
  background: none;
  border: 1px solid #fff;
}

.btn-reverse:hover,
.btn-reverse:active {
  color: #4078c0;
  background: #fff;
  border-color: #fff;
  box-shadow: none;
}

.masthead {
  padding-top: 1rem;
  padding-bottom: 1rem;
  margin-bottom: 1.5rem;
  text-align: center;
  background-color: #4078c0;
}

.masthead a {
  color: rgba(255, 255, 255, 0.5);
}

.masthead a:hover {
  color: #fff;
  text-decoration: none;
}

.masthead .masthead-logo {
  display: inline-block;
  font-size: 1.5rem;
  color: #fff;
}

.masthead .masthead-logo .mega-octicon {
  float: left;
  margin-right: .5rem;
}

@media (min-width: 34em) {
  .masthead {
    text-align: left;
  }
  .masthead .masthead-logo {
    float: left;
  }
}

.masthead-nav {
  margin-top: 1rem;
  font-size: 1rem;
}

.masthead-nav a {
  display: inline-block;
}

.masthead-nav a:not(:last-child) {
  margin-right: 1.25rem;
}

.masthead-nav .active {
  color: #fff;
  font-weight: 500;
}

@media (max-width: 34em) {
  .masthead-nav {
    padding-top: 1rem;
    border-top: 0.075rem solid rgba(255, 255, 255, 0.25);
  }
}

@media (min-width: 34em) {
  .masthead-nav {
    float: right;
    margin-top: .5rem;
  }
}

.jumbotron {
  margin-top: -2rem;
  margin-bottom: 3rem;
  padding-top: 2rem;
  padding-bottom: 4rem;
  background-color: #4078c0;
  font-size: 1.25rem;
  color: #fff;
  text-align: center;
}

.jumbotron h1 {
  font-size: 2.5em;
  font-weight: normal;
}

.jumbotron .btn {
  padding: 0.75em 1.15em;
  font-size: inherit;
  font-weight: normal;
  line-height: 1;
}

@media (min-width: 34em) {
  .jumbotron {
    padding-top: 6rem;
    padding-bottom: 8rem;
    font-size: 1.5rem;
    text-align: left;
  }
}

@media (max-width: 760px) {
  .about-that .column {
    float: none;
    width: 100%;
    margin-bottom: 30px;
  }
}

.about-that p {
  padding-right: .5rem;
  color: #555;
  line-height: 1.5;
}

.about-that h2 {
  font-weight: normal;
}

@media (max-width: 34em) {
  .docs-layout > .column {
    float: none;
    width: 100%;
  }
}

.footer {
  padding-top: 3rem;
  padding-bottom: 3rem;
  margin-top: 3rem;
  line-height: 1.75;
  color: #7a7a7a;
  border-top: 1px solid #eee;
}

.footer strong {
  color: #333;
}

.docs-menu {
  margin-bottom: 1.5rem;
  font-size: 14px;
}

@media (min-width: 34em) {
  .docs-menu {
    margin-right: 1rem;
  }
}

.docs-example {
  position: relative;
  padding: 15px;
  font-size: 13px;
  line-height: 1.4;
  border: 1px solid #e5e5e5;
  border-radius: 0.25rem 0.25rem 0 0;
}

.docs-example + .highlight {
  margin-top: -1px;
  border: 1px solid #e5e5e5;
  border-radius: 0 0 0.25rem 0.25rem;
}

.docs-example > p:last-child,
.docs-example > .menu:last-child,
.docs-example > .tabnav:last-child,
.docs-example > blockquote:last-child {
  margin-bottom: 0;
}

.docs-example .menu,
.docs-example .filter-list,
.docs-example .sunken-menu {
  max-width: 200px;
}

.docs-example .container {
  width: 100%;
  padding-left: 10px;
  padding-right: 10px;
}

.docs-example .columns + .columns {
  margin-top: 10px;
}

.docs-example .column {
  padding: 10px;
  font-family: Consolas, "Liberation Mono", Menlo, Courier, monospace;
  background-color: #e7f6e0;
  border: 1px solid #c8eab9;
}

.docs-example ul,
.docs-example ol {
  padding: 0;
  margin-top: 0;
  margin-bottom: 0;
}

.docs-example .flex-table-item > .btn {
  margin-left: 10px;
}

#markdown-toc > li:first-child {
  display: none;
}





.markdown-body h1 {
  padding-bottom: 0.3em;
  font-size: 2.25em;
  line-height: 1.2;
  border-bottom: 1px solid #eee;
}

.markdown-body h2 {
  padding-bottom: 0.3em;
  font-size: 1.75em;
  line-height: 1.225;
  border-bottom: 1px solid #eee;
}

.markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 {
  position: relative;
  margin-top: 1em;
  margin-bottom: 16px;
  font-weight: bold;
  line-height: 1.4;
}

.markdown-body > *:first-child {
  margin-top: 0 !important;
}

p {
  color: #555;
}

code {
  font-size: inherit;
}

nav.menu a {
  overflow-x: hidden;
  text-overflow: ellipsis;
}
''';

final String extraCss = '''
nav.menu a {
  overflow-x: hidden;
  text-overflow: ellipsis;
}

p {
  color: #555;
}

.deprecated,
.deprecated:hover {
  text-decoration: line-through;
}
''';
