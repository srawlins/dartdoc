// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dartdoc.tool_runner;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as pathLib;
import 'dartdoc_options.dart';

typedef ToolErrorCallback = void Function(String message);
typedef FakeResultCallback = String Function(String tool,
    {List<String> args, String content});

/// A helper class for running external tools.
class ToolRunner {
  /// Creates a new ToolRunner.
  ///
  /// Takes a [toolConfiguration] that describes all of the available tools.
  /// An optional `errorCallback` will be called for each error message
  /// generated by the tool.
  ToolRunner(this.toolConfiguration, [this._errorCallback]);

  final ToolConfiguration toolConfiguration;
  final ToolErrorCallback _errorCallback;
  int _temporaryFileCount = 0;

  Directory _temporaryDirectory;
  Directory get temporaryDirectory {
    if (_temporaryDirectory == null) {
      _temporaryDirectory =
          Directory.systemTemp.createTempSync('dartdoc_tools_');
    }
    return _temporaryDirectory;
  }

  void _error(String message) {
    if (_errorCallback != null) {
      _errorCallback(message);
    }
  }

  File _createTemporaryFile() {
    _temporaryFileCount++;
    return new File(pathLib.join(
        temporaryDirectory.absolute.path, 'input_$_temporaryFileCount'))
      ..createSync(recursive: true);
  }

  /// Must be called when the ToolRunner is no longer needed. Ideally, this is
  /// called in the finally section of a try/finally.
  ///
  /// This will remove any temporary files created by the tool runner.
  void dispose() {
    if (_temporaryDirectory != null) disposeAsync(_temporaryDirectory);
  }

  /// Avoid blocking on I/O for cleanups.
  static Future<void> disposeAsync(Directory temporaryDirectory) async {
    temporaryDirectory.exists().then((bool exists) {
      if (exists) return temporaryDirectory.delete(recursive: true);
    });
  }

  void _runSetup(
      String name, ToolDefinition tool, Map<String, String> environment) {
    bool isDartSetup = ToolDefinition.isDartExecutable(tool.setupCommand[0]);
    var args = tool.setupCommand.toList();
    String commandPath;

    if (isDartSetup) {
      commandPath = Platform.resolvedExecutable;
    } else {
      commandPath = args.removeAt(0);
    }
    _runProcess(name, '', commandPath, args, environment);
    tool.setupComplete = true;
  }

  String _runProcess(String name, String content, String commandPath,
      List<String> args, Map<String, String> environment) {
    String commandString() => ([commandPath] + args).join(' ');
    try {
      var result = Process.runSync(commandPath, args, environment: environment);
      if (result.exitCode != 0) {
        _error('Tool "$name" returned non-zero exit code '
            '(${result.exitCode}) when run as '
            '"${commandString()}" from ${Directory.current}\n'
            'Input to $name was:\n'
            '$content\n'
            'Stderr output was:\n${result.stderr}\n');
        return '';
      } else {
        return result.stdout;
      }
    } on ProcessException catch (exception) {
      _error('Failed to run tool "$name" as '
          '"${commandString()}": $exception\n'
          'Input to $name was:\n'
          '$content');
      return '';
    }
  }

  /// Run a tool.  The name of the tool is the first argument in the [args].
  /// The content to be sent to to the tool is given in the optional [content],
  /// and the stdout of the tool is returned.
  ///
  /// The [args] must not be null, and it must have at least one member (the name
  /// of the tool).
  String run(List<String> args,
      {String content, Map<String, String> environment}) {
    assert(args != null);
    assert(args.isNotEmpty);
    content ??= '';
    environment ??= <String, String>{};
    var tool = args.removeAt(0);
    if (!toolConfiguration.tools.containsKey(tool)) {
      _error('Unable to find definition for tool "$tool" in tool map. '
          'Did you add it to dartdoc_options.yaml?');
      return '';
    }
    ToolDefinition toolDefinition = toolConfiguration.tools[tool];
    var toolArgs = toolDefinition.command;
    // Ideally, we would just be able to send the input text into stdin, but
    // there's no way to do that synchronously, and converting dartdoc to an
    // async model of execution is a huge amount of work. Using dart:cli's
    // waitFor feels like a hack (and requires a similar amount of work anyhow
    // to fix order of execution issues). So, instead, we have the tool take a
    // filename as part of its arguments, and write the input to a temporary
    // file before running the tool synchronously.

    // Write the content to a temp file.
    var tmpFile = _createTemporaryFile();
    tmpFile.writeAsStringSync(content);

    // Substitute the temp filename for the "$INPUT" token, and all of the other
    // environment variables. Variables are allowed to either be in $(VAR) form,
    // or $VAR form.
    var envWithInput = {
      'INPUT': tmpFile.absolute.path,
      'TOOL_COMMAND': toolDefinition.command[0]
    }..addAll(environment);
    if (toolDefinition is DartToolDefinition) {
      // Put the original command path into the environment, because when it
      // runs as a snapshot, Platform.script (inside the tool script) refers to
      // the snapshot, and not the original script.  This way at least, the
      // script writer can use this instead of Platform.script if they want to
      // find out where their script was coming from as an absolute path on the
      // filesystem.
      envWithInput['DART_SNAPSHOT_CACHE'] =
          SnapshotCache.instance.snapshotCache.absolute.path;
      if (toolDefinition.setupCommand != null) {
        envWithInput['DART_SETUP_COMMAND'] = toolDefinition.setupCommand[0];
      }
    }
    var substitutions = envWithInput.map<RegExp, String>((key, value) {
      String escapedKey = RegExp.escape(key);
      return MapEntry(RegExp('\\\$(\\($escapedKey\\)|$escapedKey\\b)'), value);
    });
    var argsWithInput = <String>[];
    for (var arg in args) {
      var newArg = arg;
      substitutions
          .forEach((regex, value) => newArg = newArg.replaceAll(regex, value));
      argsWithInput.add(newArg);
    }

    if (toolDefinition.setupCommand != null && !toolDefinition.setupComplete)
      _runSetup(tool, toolDefinition, envWithInput);

    argsWithInput = toolArgs + argsWithInput;
    var commandPath;
    if (toolDefinition is DartToolDefinition) {
      commandPath = toolDefinition.createSnapshotIfNeeded(argsWithInput);
    } else {
      commandPath = argsWithInput.removeAt(0);
    }
    return _runProcess(tool, content, commandPath, argsWithInput, envWithInput);
  }
}