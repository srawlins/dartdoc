// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dartdoc/src/generator/generator.dart';
import 'package:dartdoc/src/generator/generator_backend.dart';
import 'package:dartdoc/src/generator/templates.dart';
import 'package:dartdoc/src/logging.dart';
import 'package:dartdoc/src/model/model.dart';
import 'package:dartdoc/src/model_utils.dart';
import 'package:dartdoc/src/runtime_stats.dart';
import 'package:dartdoc/src/warnings.dart';

/// A [Generator] that delegates rendering to a [GeneratorBackend] and delegates
/// file creation to a [FileWriter].
class GeneratorFrontEnd implements Generator {
  final GeneratorBackend _generatorBackend;

  GeneratorFrontEnd(this._generatorBackend);

  @override
  Future<void> generate(PackageGraph? packageGraph) async {
    if (_generatorBackend.templates is RuntimeTemplates) {
      packageGraph?.defaultPackage.warn(
        PackageWarning.deprecated,
        message: "The '--templates-dir' option is deprecated, and will soon no "
            'longer be supported.',
      );
    }
    if (_generatorBackend.options.resourcesDir != null) {
      packageGraph?.defaultPackage.warn(
        PackageWarning.deprecated,
        message: "The '--resources-dir' option is deprecated, and will soon be "
            'removed.',
      );
    }

    var indexElements = packageGraph == null
        ? const <Indexable>[]
        : _generateDocs(packageGraph);

    await _generatorBackend.generateAdditionalFiles();

    var categories = indexElements
        .whereType<Categorization>()
        .where((e) => e.hasCategorization)
        .toList(growable: false);
    _generatorBackend.generateCategoryJson(categories);
    _generatorBackend.generateSearchIndex(indexElements);
  }

  @override
  Set<String> get writtenFiles => _generatorBackend.writer.writtenFiles;

  /// Traverses the [packageGraph] and generates documentation for all contained
  /// elements.
  List<Indexable> _generateDocs(PackageGraph packageGraph) {
    runtimeStats.resetAccumulators({
      'writtenCategoryFileCount',
      'writtenClassFileCount',
      'writtenConstructorFileCount',
      'writtenEnumFileCount',
      'writtenExtensionFileCount',
      'writtenExtensionTypeFileCount',
      'writtenFunctionFileCount',
      'writtenLibraryFileCount',
      'writtenMethodFileCount',
      'writtenMixinFileCount',
      'writtenPackageFileCount',
      'writtenPropertyFileCount',
      'writtenSidebarFileCount',
      'writtenTopLevelPropertyFileCount',
      'writtenTypedefFileCount'
    });
    _generatorBackend.generatePackage(
        packageGraph, packageGraph.defaultPackage);

    var indexAccumulator = <Indexable>[];
    var multiplePackages = packageGraph.localPackages.length > 1;

    for (var package in packageGraph.localPackages) {
      if (multiplePackages) {
        logInfo('Generating docs for package ${package.name}...');
      }
      for (var category in package.categories.whereDocumented) {
        logInfo('Generating docs for category ${category.name} from '
            '${category.package.fullyQualifiedName}...');
        indexAccumulator.add(category);
        _generatorBackend.generateCategory(packageGraph, category);
      }

      for (var lib in package.libraries.whereDocumented) {
        if (!multiplePackages) {
          logInfo('Generating docs for library ${lib.breadcrumbName} from '
              '${lib.element.source.uri}...');
        }
        if (!lib.isAnonymous && !lib.hasDocumentation) {
          packageGraph.warnOnElement(lib, PackageWarning.noLibraryLevelDocs);
        }
        indexAccumulator.add(lib);
        _generatorBackend.generateLibrary(packageGraph, lib);

        for (var class_ in lib.allClasses.whereDocumented) {
          indexAccumulator.add(class_);
          _generatorBackend.generateClass(packageGraph, lib, class_);
        }

        for (var extension in lib.extensions.whereDocumented) {
          indexAccumulator.add(extension);
          _generatorBackend.generateExtension(packageGraph, lib, extension);
        }

        for (var extensionType in lib.extensionTypes.whereDocumented) {
          indexAccumulator.add(extensionType);
          _generatorBackend.generateExtensionType(
              packageGraph, lib, extensionType);
        }

        for (var mixin in lib.mixins.whereDocumented) {
          indexAccumulator.add(mixin);
          _generatorBackend.generateMixin(packageGraph, lib, mixin);
        }

        for (var enum_ in lib.enums.whereDocumented) {
          indexAccumulator.add(enum_);
          _generatorBackend.generateEnum(packageGraph, lib, enum_);
        }
      }
    }
    return indexAccumulator;
  }
}
