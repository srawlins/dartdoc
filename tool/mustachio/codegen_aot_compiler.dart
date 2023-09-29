// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:collection/collection.dart';
import 'package:dart_style/dart_style.dart';
import 'package:dartdoc/src/mustachio/annotations.dart';
import 'package:dartdoc/src/mustachio/parser.dart';
import 'package:dartdoc/src/mustachio/renderer_base.dart';
import 'package:dartdoc/src/type_utils.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

/// A list of [_VariableLookup]s used by a renderer constitutes a "context
/// stack".
typedef ContextStack = List<_VariableLookup>;

/// Compiles all templates specified in [specs] into a Dart library containing
/// a renderer for each template.
Future<String> compileTemplatesToRenderers(
  Set<RendererSpec> specs,
  TypeProvider typeProvider,
  TypeSystem typeSystem,
  TemplateFormat format, {
  required String root,
  required String sourcePath,
}) async {
  var buildData =
      _BuildData(typeProvider, typeSystem, format, sourcePath, root);
  for (var spec in specs) {
    var templatePath = spec.standardTemplatePaths[format]!;
    var compiler = await _AotCompiler._readAndParse(
      spec.contextType,
      spec.name,
      templatePath,
      buildData,
    );
    await compiler._compileToRenderer();
  }
  await buildData._rendererCache.deduplicateRenderers();
  var buffer = StringBuffer();
  for (var uri in buildData._referenceUris.sorted()) {
    buffer.writeln("import '$uri';");
  }

  var sortedRenderers = buildData._rendererCache.allRendererFunctions.toList()
    ..sort();
  for (var function in sortedRenderers.reversed) {
    buffer.write(function);
    buffer.writeln();
    buffer.writeln();
  }
  return DartFormatter().format('''
// GENERATED CODE. DO NOT EDIT.
//
// To change the contents of this library, make changes to the builder source
// files in the tool/mustachio/ directory.

// Some deduplicated render functions are generated but not used.
// TODO(srawlins): Detect these and do not write them.
// ignore_for_file: Xunused_element
// Sometimes we enter a new section which triggers creating a new variable, but
// the variable is not used; generally when the section is checking if a
// non-bool, non-Iterable field is non-null.
// ignore_for_file: unused_local_variable
// ignore_for_file: non_constant_identifier_names, unnecessary_string_escapes

import 'dart:convert';

$buffer

extension on StringBuffer {
  void writeEscaped(String? value) {
    write(htmlEscape.convert(value ?? ''));
  }
}
''');
}

/// Returns a method body for the render function for [compiler], which simply
/// redirects to the render function for [lubCompiler].
Future<String> _redirectingMethod(
    _AotCompiler compiler, _AotCompiler lubCompiler) async {
  var buffer = StringBuffer()..write('String ${compiler._rendererName}');

  buffer.writeTypeParameters(
      compiler._usedContextStack.expand((c) => c.type.element.typeParameters));
  buffer.write('(');

  for (var context in compiler._usedContextStack) {
    var contextElement = context.type.element;
    buffer.write(contextElement.displayName);
    if (contextElement.typeParameters.isNotEmpty) {
      buffer.write('<');
    }
    for (var tp in contextElement.typeParameters) {
      buffer.write(tp.name);
      if (tp != contextElement.typeParameters.last) {
        buffer.write(', ');
      }
    }
    if (contextElement.typeParameters.isNotEmpty) {
      buffer.write('>');
    }
    buffer.write(' ${context.name}');
  }
  buffer.writeln(') => ${lubCompiler._rendererName}(');
  for (var context in compiler._usedContextStack) {
    buffer.write(context.name);
    if (context != compiler._usedContextStack.last) {
      buffer.write(', ');
    }
  }
  buffer.write(');');
  return buffer.toString();
}

/// A class which compiles a single template file into a renderer Dart function,
/// and possible support functions for partial templates.
class _AotCompiler {
  /// The template to be compiled.
  final String _templatePath;

  /// The context type which is to be rendered into the compiled template.
  final InterfaceType _contextType;

  /// The name of the renderer, which is either a public name (for top-level
  /// renderers specified in a `@Renderer` annotation), or a private name for
  /// a partial.
  final String _rendererName;

  final _BuildData _buildData;

  /// The parsed syntax tree of the template at [_templatePath].
  final List<MustachioNode> _syntaxTree;

  /// The set of compilers for all referenced partials.
  ///
  /// This field is only complete after [_compileToRenderer] has run.
  final Set<_AotCompiler> _partialCompilers = {};

  /// The current stack of context objects (as variable lookups).
  final ContextStack _contextStack;

  /// The set of context objects which are ultimately used by this compiler.
  ///
  /// This field is only complete after [_compileToRenderer] has run.
  final Set<_VariableLookup> _usedContexts = {};

  ContextStack get _usedContextStack =>
      [..._contextStack.where(_usedContexts.contains)];

  /// A counter for naming partial render functions.
  ///
  /// Incrementing the counter keeps names unique.
  int _partialCounter = 0;

  /// A counter for naming context variables.
  ///
  /// Incrementing the counter keeps names unique.
  int _contextNameCounter;

  /// Reads the template at [templatePath] and parses it into a syntax tree,
  /// returning an [_AotCompiler] with the necessary information to be able to
  /// compile the template into a renderer.
  static Future<_AotCompiler> _readAndParse(
    InterfaceType contextType,
    String rendererName,
    String templatePath,
    _BuildData buildData, {
    ContextStack contextStack = const [],
  }) async {
    var template =
        await File(path.join(buildData._root, templatePath)).readAsString();
    var syntaxTree = MustachioParser(template, templatePath).parse();
    return _AotCompiler._(
        contextType, rendererName, templatePath, syntaxTree, buildData,
        contextStack: contextStack);
  }

  _AotCompiler._(
    this._contextType,
    this._rendererName,
    this._templatePath,
    this._syntaxTree,
    this._buildData, {
    required ContextStack contextStack,
  })  : _contextStack = _rename(contextStack),
        _contextNameCounter = contextStack.length;

  /// Returns a copy of [original], replacing each variable's name with
  /// `context0` through `contextN` for `N` variables.
  ///
  /// This ensures that each renderer accepts a simple list of context objects
  /// with predictable names.
  static ContextStack _rename(ContextStack original) {
    var result = <_VariableLookup>[];
    var index = original.length - 1;
    for (var variable in original) {
      result.push(_VariableLookup(variable.type, 'context$index',
          indexInParent: original.indexOf(variable)));
      index--;
    }
    return [...result.reversed];
  }

  Future<_RendererData> _compileToRenderer({bool useCache = true}) async {
    if (_contextStack.isEmpty) {
      var contextVariable = _VariableLookup(_contextType, 'context0');
      _contextStack.push(contextVariable);
      _contextNameCounter++;
    }

    var blockCompiler = _BlockCompiler(this, _contextStack);
    await blockCompiler._compile(_syntaxTree);
    var rendererBody = blockCompiler._buffer.toString();
    _usedContexts.addAll(_contextStack
        .where((c) => blockCompiler._usedContextTypes.contains(c)));

    if (useCache) {
      var cachedData =
          await _buildData._rendererCache.get(_templatePath, _usedContextStack);
      if (cachedData != null) {
        // No need to keep compiling a new renderer.
        return cachedData;
      }
    }

    _buildData._referenceUris.addAll(blockCompiler._referenceUris);

    var buffer = StringBuffer()..write('String $_rendererName');

    // Get the type parameters of _each_ of the context types in the stack,
    // including their bounds, concatenate them, and wrap them in angle
    // brackets.
    // TODO(srawlins): This will produce erroneous code if any two context types
    // have type parameters with the same name. Something like:
    //     _renderFoo_partial_bar_1<T, T>(Baz<T> context1, Foo<T> context0)
    // Rename type parameters to some predictable collision-free naming scheme;
    // the body of the function should not reference the type parameters, so
    // this should be perfectly possible.

    var referenceElements = buffer.writeTypeParameters(
      _usedContexts.expand((c) => c.type.element.typeParameters),
    );
    for (var element in referenceElements) {
      _buildData._referenceUris.add(_elementUri(element));
    }
    buffer.write('(');

    for (var context in _usedContexts) {
      var contextElement = context.type.element;
      _buildData._referenceUris.add(_elementUri(contextElement));
      buffer.write(contextElement.displayName);
      if (contextElement.typeParameters.isNotEmpty) {
        buffer.write('<');
      }
      for (var tp in contextElement.typeParameters) {
        buffer.write(tp.name);
        if (tp != contextElement.typeParameters.last) {
          buffer.write(', ');
        }
      }
      if (contextElement.typeParameters.isNotEmpty) {
        buffer.write('>');
      }
      buffer.write(' ${context.name}');
    }

    buffer.write(''') {
  final buffer = StringBuffer();
  $rendererBody
  return buffer.toString();
}
''');

    return _buildData._rendererCache
        .put(_templatePath, _usedContextStack, this, buffer.toString());
  }

  /// Returns the URI of [element] for use in generated import directives.
  String _elementUri(Element element) {
    var libraryElement = element.library!;
    var libraryUri = libraryElement.source.uri;
    if (libraryUri.scheme == 'file') {
      return path.relative(libraryUri.path,
          from: path.absolute(path.dirname(_buildData._sourcePath)));
    }
    return libraryUri.toString();
  }
}

/// A class which can compile a Mustache block of nodes into Dart source for a
/// renderer.
class _BlockCompiler {
  final _AotCompiler _templateCompiler;

  final ContextStack _contextStack;

  final Set<_VariableLookup> _usedContextTypes = {};

  /// The set of URIs of elements that need to be imported.
  final Set<String> _referenceUris = {};

  final _buffer = StringBuffer();

  _BlockCompiler(this._templateCompiler, this._contextStack);

  void write(String text) => _buffer.write(text);

  void writeln(String text) => _buffer.writeln(text);

  InterfaceType get contextType => _contextStack.first.type;

  String get contextName => _contextStack.first.name;

  TemplateFormat get format => _templateCompiler._buildData._format;

  TypeProvider get typeProvider => _templateCompiler._buildData._typeProvider;

  TypeSystem get typeSystem => _templateCompiler._buildData._typeSystem;

  /// Generates a new name for a context variable. Each context variable going
  /// up the stack needs to be accessible, so they each need a unique variable
  /// name.
  String getNewContextName() {
    var newContextName = 'context${_templateCompiler._contextNameCounter}';
    _templateCompiler._contextNameCounter++;
    return newContextName;
  }

  /// The base name of a partial rendering function.
  String get partialBaseName => '_${_templateCompiler._rendererName}_partial';

  Future<void> _compile(List<MustachioNode> syntaxTree) async {
    for (var node in syntaxTree) {
      switch (node) {
        case Text():
          _writeText(node.content);
        case Variable():
          var variableLookup = _lookUpGetter(node);
          _writeGetter(variableLookup, escape: node.escape);
        case Section():
          await _compileSection(node);
        case Partial():
          await _compilePartial(node, _referenceUris);
      }
    }
  }

  /// Compiles [node] into a renderer's Dart source.
  Future<void> _compilePartial(Partial node, Set<String> referenceUris) async {
    var extension = format == TemplateFormat.html ? 'html' : 'md';
    var filePath = node.key.split('/');
    var fileName = filePath.removeLast();
    filePath.add('_$fileName.$extension');
    var partialPath = path.join(
        path.dirname(_templateCompiler._templatePath), filePath.join('/'));
    // First see if there is a compiler in the global cache.
    var sanitizedKey = node.key.replaceAll('.', '_').replaceAll('/', '_');
    var name = '${partialBaseName}_'
        '${sanitizedKey}_'
        '${_templateCompiler._partialCounter}';
    var potentialPartialCompiler = await _AotCompiler._readAndParse(
        contextType, name, partialPath, _templateCompiler._buildData,
        contextStack: _contextStack);
    await potentialPartialCompiler._compileToRenderer();
    var partialCompiler = (await _templateCompiler._buildData._rendererCache
            .get(partialPath, potentialPartialCompiler._usedContextStack))
        ?.compiler;
    // If we don't have an existing one, then use the one we just created.
    partialCompiler ??= potentialPartialCompiler;
    _templateCompiler._partialCompilers.add(partialCompiler);
    _templateCompiler._partialCounter++;
    // Call the partial's renderer function here; the definition of the renderer
    // function is written later.
    write('buffer.write(');
    writeln('${partialCompiler._rendererName}(');
    var usedContextStack = partialCompiler._usedContexts
        .map((context) => context.indexInParent!)
        .map((index) => _contextStack[index]);
    writeln(usedContextStack.map((c) => c.name).join(','));
    _usedContextTypes.addAll(usedContextStack);
    writeln('));');
  }

  /// Compiles [node] into a renderer's Dart source.
  Future<void> _compileSection(Section node) async {
    var variableLookup = _lookUpGetter(node);
    if (variableLookup.type.isDartCoreBool) {
      // Conditional block.
      await _compileConditionalSection(variableLookup, node.children,
          invert: node.invert);
    } else if (typeSystem.isAssignableTo(
        variableLookup.type, typeProvider.iterableDynamicType)) {
      // Repeated block.
      await _compileRepeatedSection(variableLookup, node.children,
          invert: node.invert);
    } else {
      // Use accessor value as context.
      await _compileValueSection(variableLookup, node.children,
          invert: node.invert);
    }
  }

  /// Compiles a conditional section containing [block] into a renderer's Dart
  /// source.
  Future<void> _compileConditionalSection(
      _VariableLookup variableLookup, List<MustachioNode> block,
      {bool invert = false}) async {
    var variableAccess = variableLookup.name;
    if (invert) {
      writeln('if ($variableAccess != true) {');
    } else {
      writeln('if ($variableAccess == true) {');
    }
    await _compile(block);
    writeln('}');
  }

  /// Compiles a repeated section containing [block] into a renderer's Dart
  /// source.
  Future<void> _compileRepeatedSection(
      _VariableLookup variableLookup, List<MustachioNode> block,
      {bool invert = false}) async {
    var variableIsPotentiallyNullable =
        typeSystem.isPotentiallyNullable(variableLookup.type);
    var variableAccess = variableLookup.name;
    if (invert) {
      if (variableIsPotentiallyNullable) {
        writeln('if ($variableAccess?.isEmpty ?? true) {');
      } else {
        writeln('if ($variableAccess.isEmpty) {');
      }
      await _compile(block);
      writeln('}');
    } else {
      var variableAccessResult = getNewContextName();
      writeln('var $variableAccessResult = $variableAccess;');
      var newContextName = getNewContextName();
      if (variableIsPotentiallyNullable) {
        writeln('if ($variableAccessResult != null) {');
      }
      writeln('  for (var $newContextName in $variableAccessResult) {');
      // If [loopType] is something like `C<int>` where
      // `class C<T> implements Queue<Future<T>>`, we need the [ClassElement]
      // for [Iterable], and then use [DartType.asInstanceOf] to ultimately
      // determine that the inner type of the loop is, for example,
      // `Future<int>`.
      var iterableElement = typeProvider.iterableElement;
      var iterableType = variableLookup.type.asInstanceOf(iterableElement)!;
      var innerContextType = iterableType.typeArguments.first as InterfaceType;
      var innerContext = _VariableLookup(innerContextType, newContextName);
      _contextStack.push(innerContext);
      await _compile(block);
      _contextStack.pop();
      writeln('  }');
      if (variableIsPotentiallyNullable) {
        writeln('}');
      }
    }
  }

  /// Compiles a value section containing [block] into a renderer's Dart source.
  Future<void> _compileValueSection(
      _VariableLookup variableLookup, List<MustachioNode> block,
      {bool invert = false}) async {
    var variableAccess = variableLookup.name;
    var variableIsPotentiallyNullable =
        typeSystem.isPotentiallyNullable(variableLookup.type);
    if (invert) {
      writeln('if ($variableAccess == null) {');
      await _compile(block);
      writeln('}');
    } else {
      var innerContextName = getNewContextName();
      writeln('var $innerContextName = $variableAccess;');
      if (variableIsPotentiallyNullable) {
        writeln('if ($innerContextName != null) {');
      }
      var innerContext = _VariableLookup(
          typeSystem.promoteToNonNull(variableLookup.type) as InterfaceType,
          innerContextName);
      _contextStack.push(innerContext);
      await _compile(block);
      _contextStack.pop();
      if (variableIsPotentiallyNullable) {
        writeln('}');
      }
    }
  }

  /// Returns a valid [_VariableLookup] on a Mustache node, [node] by resolving
  /// its key.
  _VariableLookup _lookUpGetter(HasMultiNamedKey node) {
    var key = node.key;

    // '.' is an entirely special case.
    if (key.length == 1 && key[0] == '.') {
      _usedContextTypes.add(_contextStack.first);
      return _VariableLookup(contextType, contextName);
    }

    var primaryName = key[0];

    late _VariableLookup context;
    PropertyAccessorElement? getter;
    for (var c in _contextStack) {
      getter = c.type.lookUpGetter2(primaryName, contextType.element.library);
      if (getter != null) {
        context = c;
        _usedContextTypes.add(c);
        break;
      }
    }
    if (getter == null) {
      var contextTypes = [for (var c in _contextStack) c.type];
      throw MustachioResolutionError(node.keySpan
          .message("Failed to resolve '$key' as a property on any types in the "
              'context chain: $contextTypes'));
    }

    var type = getter.returnType as InterfaceType;
    var contextChain = typeSystem.isPotentiallyNullable(context.type)
        // This is imperfect; the idea is that in our templates, we may have
        // `{{foo.bar.baz}}` and `foo.bar` may be nullably typed. Mustache
        // (and Mustachio) does not have a null-aware property access
        // operator, nor a null-check operator. This code translates
        // `foo.bar.baz` to `foo.bar!.baz` for nullable `foo.bar`.
        ? '${context.name}!.$primaryName'
        : '${context.name}.$primaryName';
    var remainingNames = [...key.skip(1)];
    for (var secondaryKey in remainingNames) {
      getter = type.lookUpGetter2(secondaryKey, type.element.library);
      if (getter == null) {
        throw MustachioResolutionError(node.keySpan.message(
            "Failed to resolve '$secondaryKey' on ${context.type} while "
            'resolving $remainingNames as a property chain on any types in '
            'the context chain: $contextChain, after first resolving '
            "'$primaryName' to a property on $type"));
      }
      contextChain = typeSystem.isPotentiallyNullable(type)
          ? '$contextChain!.$secondaryKey'
          : '$contextChain.$secondaryKey';
      type = getter.returnType as InterfaceType;
    }
    return _VariableLookup(type, contextChain);
  }

  /// Writes [content] to the generated render functions as text, properly
  /// handling newlines, quotes, and other special characters.
  void _writeText(String content) {
    if (content.isEmpty) return;
    if (content == '\n') {
      // Blank lines happen a lot; just indicate them as such.
      writeln('buffer.writeln();');
    } else {
      content = content
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'")
          .replaceAll(r'$', r'\$');
      if (_multipleWhitespacePattern.hasMatch(content)) {
        write("buffer.write('");
        write(content.replaceAll('\n', '\\n'));
        writeln("');");
      } else {
        if (content[0] == '\n') {
          write('buffer.writeln();');
        }
        write("buffer.write('''");
        write(content);
        writeln("''');");
      }
    }
  }

  /// A pattern for a String containing only space and newlines, more than one.
  static final RegExp _multipleWhitespacePattern = RegExp('^[ \\n]+\$');

  /// Writes a call to [variableLookup] to the renderer.
  ///
  /// The result is HTML-escaped if [escape] is true.
  void _writeGetter(_VariableLookup variableLookup, {bool escape = true}) {
    var variableAccess = variableLookup.name;
    var toString = variableLookup.type.isDartCoreString
        ? variableAccess
        : typeSystem.isPotentiallyNullable(variableLookup.type)
            ? '$variableAccess?.toString()'
            : '$variableAccess.toString()';
    writeln(escape
        ? 'buffer.writeEscaped($toString);'
        : 'buffer.write($toString);');
  }
}

/// Various static build data to be used for each renderer, including specified
/// renderers and template renderers.
@immutable
class _BuildData {
  final TypeProvider _typeProvider;

  final TypeSystem _typeSystem;

  final TemplateFormat _format;

  final String _sourcePath;

  final String _root;

  final Set<String> _referenceUris = {};

  final _RendererCache _rendererCache;

  _BuildData(this._typeProvider, this._typeSystem, this._format,
      this._sourcePath, this._root)
      : _rendererCache = _RendererCache(_typeSystem);
}

/// A cache which maps template paths to the various compilers and renderer data
/// that may be used to render them.
class _RendererCache {
  final Map<String, _RenderersForPath> _renderers = {};
  final TypeSystem _typeSystem;

  _RendererCache(this._typeSystem);

  /// Returns the renderer data for [templatePath] and [usedContextStack], or
  /// `null` if there is no such data.
  Future<_RendererData?> get(
          String templatePath, ContextStack usedContextStack) async =>
      _renderers[templatePath]?.getSuitable(usedContextStack);

  /// Returns the compiler for [templatePath] and [usedContextStack], or `null`
  /// if there is no such compiler in the cache.
  _AotCompiler? getCompiler(
          String templatePath, ContextStack usedContextStack) =>
      _renderers[templatePath]?.get(usedContextStack)?.compiler;

  /// Inserts
  _RendererData put(
    String templatePath,
    ContextStack usedContextStack,
    _AotCompiler compiler,
    String renderer,
  ) {
    return _renderers
        .putIfAbsent(templatePath, () => _RenderersForPath(_typeSystem))
        .put(usedContextStack, compiler, renderer);
  }

  void remove(String templatePath, ContextStack usedContextStack) =>
      _renderers[templatePath]?.remove(usedContextStack);

  /// Deduplicates multiple renderers which are each used to render a partial
  /// into a single renderer.
  ///
  /// When a partial is referenced by more than one template, multiple compilers
  /// are used to build multiple render functions, because the context stack of
  /// types may be different in each case. But it is perfectly logical to expect
  /// that these can be deduplicated, as they should be able to use one common
  /// context stack of interfaces.
  ///
  /// Attempts to deduplicate the compilers (which build the renderers) by
  /// replacing context types in each stack with their collective LUB.
  Future<void> deduplicateRenderers() async {
    // Map each template (represented by its path) to the list of compilers which
    // compile it to a renderer function.
    for (var templatePath in _renderers.keys) {
      var contextStacks = allContextStacksFor(templatePath);
      if (contextStacks.length < 2) {
        // Nothing to deduplicate; there is only one context stack, and therefore
        // only one generated renderer function.
        continue;
      }

      // Each of the render functions generated by a compiler for this asset can
      // be replaced by a more generic renderer which accepts the LUB types. The
      // body of each replaced renderer can perform a simple redirect to the more
      // generic renderer.
      await _renderers[templatePath]!
          .deduplicateRenderers(templatePath, contextStacks);
    }
  }

  List<ContextStack> allContextStacksFor(String templatePath) =>
      _renderers[templatePath]!._renderers.keys.toList();

  Iterable<_AotCompiler>? allCompilersFor(String templatePath) =>
      _renderers[templatePath]?._renderers.values.map((e) => e.compiler);

  Iterable<String> get allRendererFunctions => _renderers.values
      .expand((e) => e._renderers.values.map((f) => f.renderer));
}

class _RenderersForPath {
  final Map<ContextStack, _RendererData> _renderers = {};
  final TypeSystem _typeSystem;

  _RenderersForPath(this._typeSystem);

  /// Gets renderer data for [contextStack] or render data for a suitable
  /// replacement for [contextStack], if a suitable replacement exists.
  ///
  /// A suitable replacement is a [ContextStack] where each type is a supertype
  /// of the corresponding type in [contextStack].
  Future<_RendererData?> getSuitable(ContextStack contextStack) async {
    var keys = [..._renderers.keys];
    for (var existingContextStack in keys) {
      var lubSomething =
          _typeSystem.contextStackLub([contextStack, existingContextStack]);
      if (lubSomething == null) continue;
      var lubIsSameAsExisting = true;
      for (var i = 0; i < existingContextStack.length; i++) {
        // TODO is equality good enough?
        if (lubSomething[i] != existingContextStack[i].type) {
          lubIsSameAsExisting = false;
          break;
        }
      }
      if (lubIsSameAsExisting) {
        // Do not create a deduplicated renderer; all we need is
        // [existingContextStack].
        var data = _renderers[existingContextStack]!;
        data.referenceCount++;
        return data;
      } else {
        // The existing context stack and [contextStack] have a good LUB set of
        // types, so create a deduplicated renderer.
        var existingCompiler = get(existingContextStack)!.compiler;
        var data = await deduplicateRenderers(
          existingCompiler._templatePath,
          [contextStack, existingContextStack],
        );
        if (data == null) {
          // Could not compile a renderer for the LUB of the two context stacks.
          continue;
        }
      }
    }
    return null;
  }

  _RendererData? get(ContextStack key) {
    var existingKey = _existingKey(key);
    return (existingKey == null) ? null : _renderers[existingKey]!;
  }

  ContextStack? _existingKey(ContextStack key) {
    return _renderers.keys.firstWhereOrNull((k) {
      if (key.length != k.length) return false;
      for (var i = 0; i < key.length; i++) {
        if (key[i] != k[i]) {
          return false;
        }
      }
      return true;
    });
  }

  /// Inserts [compiler] and [renderer] as the data for [contextStack].
  _RendererData put(
      ContextStack contextStack, _AotCompiler compiler, String renderer) {
    var existingContextStack = _existingKey(contextStack);
    if (existingContextStack == null) {
      var data = _RendererData(compiler, renderer);
      _renderers[contextStack] = data;
      return data;
    }
    var data = _renderers[existingContextStack]!;
    var newData = _RendererData(compiler, renderer)
      ..referenceCount = data.referenceCount;
    _renderers[existingContextStack] = newData;
    return newData;
  }

  /// Decrements the renderer data 'references' counter for [contextStack], if
  /// it exists, and removes the data if the references counter is now 0.
  void remove(ContextStack contextStack) {
    var existingContextStack = _existingKey(contextStack);
    if (existingContextStack == null) return;
    var usage = _renderers[existingContextStack]!;
    usage.referenceCount--;
    if (usage.referenceCount == 0) {
      _renderers.remove(existingContextStack);
    }
  }

  Future<_RendererData?> deduplicateRenderers(
    String templatePath,
    List<ContextStack> contextStacks,
  ) async {
    var contextStackTypes = _typeSystem.contextStackLub(contextStacks);
    if (contextStackTypes == null) {
      // The stack lengths are different; it is impossible to fully deduplicate
      // such partial renderers.
      return null;
    }

    var partialsCompilersToRemove = <_AotCompiler>{};
    void removeUnusedPartials(_AotCompiler c) {
      for (var partial in c._partialCompilers) {
        removeUnusedPartials(partial);
      }
      partialsCompilersToRemove.add(c);
    }

    var rendererName = templatePath.replaceAll('.', '_').replaceAll('/', '_');
    var firstCompiler = _renderers.values.map((e) => e.compiler).first;
    var lubCompiler = _AotCompiler._(
      contextStackTypes.first,
      '_deduplicated_$rendererName',
      templatePath,
      firstCompiler._syntaxTree,
      firstCompiler._buildData,
      contextStack: [
        ...contextStackTypes.map((t) => _VariableLookup(t, 'UNUSED'))
      ],
    );
    _RendererData data;
    try {
      data = await lubCompiler._compileToRenderer(useCache: false);
      // ignore: avoid_catching_errors
    } on MustachioResolutionError {
      // Oops, switching to the LUB type prevents the renderer from compiling;
      // likely the properties accessed in the partial are not all declared on
      // the LUB type.
      var compilers = _renderers.values.map((e) => e.compiler);
      var names = compilers.map((c) => "'${c._rendererName}'");
      if (names.length > 5) {
        names = [...names.take(5), '... (${names.length - 5} more)'];
      }
      print("Could not deduplicate '$templatePath' with context types: "
          '$contextStackTypes, from ${names.join(', ')}');
      // Any partials generated before the exception was thrown are not needed.
      removeUnusedPartials(lubCompiler);
      for (var compiler in partialsCompilersToRemove) {
        remove(compiler._usedContextStack);
      }
      return null;
    }

    for (var contextStack in contextStacks) {
      var compiler = get(contextStack)?.compiler;
      if (compiler != null) {
        put(
          contextStack,
          compiler,
          await _redirectingMethod(compiler, lubCompiler),
        );
        for (var c in compiler._partialCompilers) {
          removeUnusedPartials(c);
        }
      }
    }

    for (var compiler in partialsCompilersToRemove) {
      remove(compiler._usedContextStack);
    }

    return data;
  }
}

/// The data for the usage of a [renderer], generated by a [compiled], and
/// referemced [referenes] times.
class _RendererData {
  final _AotCompiler compiler;
  final String renderer;
  int referenceCount = 0;

  _RendererData(this.compiler, this.renderer);
}

/// Represents a variable lookup via property access chain [name] which returns
/// an object of type [type].
@immutable
class _VariableLookup {
  final InterfaceType type;

  final String name;

  /// The index of this variable in the declaring compiler's parent compiler's
  /// context stack, if it was declared in the construction of a compiler.
  final int? indexInParent;

  _VariableLookup(this.type, this.name, {this.indexInParent});
}

extension<T> on List<T> {
  void push(T value) => insert(0, value);

  T pop() => removeAt(0);
}

extension on StringBuffer {
  Set<Element> writeTypeParameters(
      Iterable<TypeParameterElement> typeParameters) {
    var referencedElements = <Element>{};
    var hasTypeParameters = false;
    for (var typeParameter in typeParameters) {
      if (!hasTypeParameters) {
        write('<');
      } else {
        write(', ');
      }
      hasTypeParameters = true;

      var bound = typeParameter.bound;
      if (bound == null) {
        write(typeParameter.name);
      } else {
        var boundElement = bound.documentableElement!;
        referencedElements.add(boundElement);
        write('${typeParameter.name} extends ${boundElement.name!}');
      }
    }
    if (hasTypeParameters) {
      write('>');
    }
    return referencedElements;
  }
}

extension on TypeSystem {
  /// Returns a list of types which represents the LUB of each of the types in
  /// the corresponding positions in [contextStacks].
  List<InterfaceType>? contextStackLub(List<ContextStack> contextStacks) {
    // The length of each and every context stack.
    var contextStacksLength = contextStacks.first.length;
    if (contextStacks.any((s) => s.length != contextStacksLength)) {
      return null;
    }

    // The new list of context types, each of which is the LUB of the associated
    // context type of each of the compilers.
    var contextStackTypes = <InterfaceType>[];
    for (var i = 0; i < contextStacksLength; i++) {
      var types = contextStacks.map((s) => s[i].type);
      var lubType =
          types.fold<DartType>(types.first, leastUpperBound) as InterfaceType;
      contextStackTypes.add(lubType);
    }

    return contextStackTypes;
  }
}
