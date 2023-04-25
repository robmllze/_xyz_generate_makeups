// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//
// XYZ Generate Makeups
//
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

import "dart:io";

import "package:build/build.dart";
import "package:analyzer/dart/element/element.dart";
import "package:source_gen/source_gen.dart";

import "package:xyz_generate_makeups_annotations/xyz_generate_makeups_annotations.dart";
import "package:xyz_utils/xyz_utils_non_web.dart";

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

Builder makeupsBuilder(BuilderOptions options) => MakeupsBuilder();

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

class MakeupsGenerator extends GeneratorForAnnotation<GenerateMakeups> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    final classElement = element as ClassElement;

    // [1] Get the list of makeup parameters from the @GenerateMakeups
    // annotation.
    final makeupParameters = annotation.read("parameters").mapValue.map(
      (final key, final value) {
        return MapEntry(
          key?.toStringValue(),
          value?.toStringValue(),
        );
      },
    ).nullsRemoved();
    if (makeupParameters.isEmpty) {
      makeupParameters["dummy"] = "String?";
    }
    final makeupParametersEntries = makeupParameters.entries.toList()
      ..sort(
        (final a, final b) {
          return a.key.compareTo(b.key);
        },
      );
    final makeupParametersSorted = Map.fromEntries(makeupParametersEntries);

    // [2] Map the file name to other names to use below...
    final widgetFileName = buildStep.inputId.pathSegments.last;
    final widgetFileNameWithoutExtension = widgetFileName.split(".").tryFirst ?? widgetFileName;
    final makeupFileRootName = widgetFileNameWithoutExtension.replaceAll(RegExp(r"[_]*my_"), "");
    final makeupRootName = makeupFileRootName.toCamelCase();
    final makeupClassRootName = makeupFileRootName.toCamelCaseCapitalized();
    final makeupClassName = "Makeup$makeupClassRootName";
    final makeupDirectory = "lib/widgets/$widgetFileNameWithoutExtension/makeup/";
    final srcDirectory = "$makeupDirectory/src/";
    final makeupClassFilePath = "${srcDirectory}_parent.g.dart";
    final exportsFilePath = "${srcDirectory}makeup.g.dart";
    final dependenciesFilePath = "${srcDirectory}_dependencies.dart";

    // [3] Add all fields annotated with @MakeupParameter to makeupParameters.
    final fields = classElement.fields;
    for (final field in fields) {
      // Check if the field has the @MakeupParameter annotation.
      final hasAnnotation = field.metadata.any(
        (final annotation) {
          return annotation
                  .computeConstantValue()
                  ?.type
                  ?.getDisplayString(withNullability: false) ==
              "MakeupParameter";
        },
      );
      // If the field has the @MakeupParameter annotation, add it to the list
      // of parameters.
      if (hasAnnotation) {
        final name = field.name;
        final type = field.type.getDisplayString(withNullability: true);
        makeupParametersSorted[name] = type;
      }
    }

    // [4] Generate the makeup class file.
    await _generateMakeupClass(
      makeupClassFilePath: makeupClassFilePath,
      makeupClassName: makeupClassName,
      widgetFileNameWithoutExtension: widgetFileNameWithoutExtension,
      makeupParameters: makeupParametersSorted,
    );

    // [5] Get the list of makeup names from the @GenerateMakeups annotation,
    // and add "default" to the list.
    final makeupNames = annotation
        .read("names")
        .setValue
        .map((final object) => object.toStringValue()?.toLowerCase())
        .nullsRemoved()
        .toSet();

    // Ensure the defailt makeup is always included.
    makeupNames.add("${makeupRootName}Default");

    // Get and add any makeup names from "my_theme.dart".
    final moreMakeupNames = await _getMakeupNamesFromThemeClassFile(
      fileName: "my_theme.dart",
      makeupClassName: makeupClassName,
      makeupRootName: makeupRootName,
    );
    makeupNames.addAll(moreMakeupNames);

    final templateFileNames = <String>{};

    for (final makeupName in makeupNames) {
      // [6] Create a name for the makeup template file.
      final temp = "_makeup_${makeupName.toSnakeCase()}.dart";
      templateFileNames.add(temp);

      // [7] Generate the makeup template.
      final makeupTemplateFilePath = "lib/widgets/$widgetFileNameWithoutExtension/makeup/$temp";
      await _generateNamedMakeupTemplate(
        makeupClassName: makeupClassName,
        makeupClassRootName: makeupClassRootName,
        makeupName: makeupName,
        makeupParameters: makeupParametersSorted,
        makeupRootName: makeupRootName,
        makeupTemplateFilePath: makeupTemplateFilePath,
      );
    }

    // [8] Generate the exports file.
    await _generateExportsFile(
      exportsFilePath: exportsFilePath,
      templateFileNames: templateFileNames,
    );

    // [9] Generate the imports file.
    await _generateDependenciesFile(dependenciesFilePath: dependenciesFilePath);

    return "";
  }
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

class MakeupsBuilder extends SharedPartBuilder {
  MakeupsBuilder() : super([MakeupsGenerator()], "makeups_builder");
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

Future<List<String>> _getMakeupNamesFromThemeClassFile({
  required String fileName,
  required String makeupClassName,
  required String makeupRootName,
}) async {
  try {
    final file = (await findFileByName(fileName, "lib/themes/"))!;
    final exists = await file.exists();
    if (!exists) return [];
    final type = "F$makeupClassName";
    final data = await file.readAsString();
    // Get all the substrings located between the specified type and the semicolon.
    final matches = RegExp("$type\\s+([^;]+);").allMatches(data);
    final substrings = matches.map((final l) => l.group(1)).nullsRemoved();
    // Get all the member names.
    final members = substrings.map((final l) {
      return l.replaceAll(RegExp("\\s"), "").split(",");
    }).tryReduce()!;
    return members.toList();
  } catch (_) {
    return [];
  }
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

Future<void> _generateMakeupClass({
  required String makeupClassFilePath,
  required String makeupClassName,
  required String widgetFileNameWithoutExtension,
  required Map<String, String> makeupParameters,
}) async {
  final file = File(makeupClassFilePath);
  final exists = await file.exists();
  if (exists) await file.delete();
  final lines = [
    "// GENERATED CODE - DO NOT MODIFY BY HAND",
    "",
    "// ignore_for_file: unused_import",
    "import 'package:flutter/material.dart';",
    "import '/all.dart';",
    "import '_dependencies.dart';",
    "",
    "class $makeupClassName {",
    ...makeupParameters.entries.map((final parameter) {
      final name = parameter.key;
      final type = parameter.value;
      return "  $type $name;";
    }),
    "",
    "  $makeupClassName({",
    ...makeupParameters.entries.map((final parameter) {
      final name = parameter.key;
      final type = parameter.value;
      final isNullable = type.endsWith("?");
      final maybeRequired = isNullable ? "" : "required ";
      return "    ${maybeRequired}this.$name,";
    }),
    "  });",
    "",
    "  $makeupClassName copyWith({",
    ...makeupParameters.entries.map((final parameter) {
      final name = parameter.key;
      final type = "${parameter.value}?".replaceAll("??", "?");
      return "    $type $name,";
    }),
    "  }) {",
    "    return $makeupClassName(",
    ...makeupParameters.keys.map((final name) {
      return "      $name: $name ?? this.$name,";
    }),
    "    );",
    "  }",
    "}",
    "",
    "typedef F$makeupClassName = $makeupClassName Function();",
  ].join("\n");
  await file.create(recursive: true);
  await file.writeAsString(
    lines,
    flush: true,
  );
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

Future<void> _generateNamedMakeupTemplate({
  required String makeupTemplateFilePath,
  required String makeupClassName,
  required String makeupRootName,
  required String makeupClassRootName,
  required String makeupName,
  required Map<String, String> makeupParameters,
}) async {
  final file = File(makeupTemplateFilePath);
  final exists = await file.exists();
  if (!exists) {
    final isDefault = makeupName == "${makeupRootName}Default";
    final function = "makeup${makeupName.capitalize()}";
    final result = isDefault
        ? "return $makeupClassName"
        : "final parent = makeup${makeupClassRootName}Default();"
            "\n"
            "  return parent.copyWith";
    final lines = [
      "// To regenerate this file, delete it and run `flutter pub run build_runner build`",
      "",
      "// ignore_for_file: unused_import",
      "// ignore_for_file: unnecessary_import",
      "import \"package:flutter/material.dart\";",
      "import \"/all.dart\";",
      "import 'src/makeup.g.dart';",
      "import 'src/_dependencies.dart';",
      "",
      "$makeupClassName $function() {",
      if (isDefault) "// ignore: prefer_const_constructors",
      "  $result(",
      ...makeupParameters.keys.map((final name) => "    $name: null,"),
      "  );",
      "}",
    ].join("\n");
    await file.create(recursive: true);
    await file.writeAsString(
      lines,
      flush: true,
    );
  }
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

Future<void> _generateExportsFile({
  required String exportsFilePath,
  required Set<String> templateFileNames,
}) async {
  final file = File(exportsFilePath);
  final exists = await file.exists();
  if (exists) await file.delete();
  final lines = [
    "// GENERATED CODE - DO NOT MODIFY BY HAND",
    "",
    // [1/2] Export the makeup class file.
    "export '_parent.g.dart';",
    // [2/2] Export the makeup template files.
    ...templateFileNames.map((final fileName) => "export '../$fileName';"),
  ].join("\n");

  await file.create(recursive: true);
  await file.writeAsString(
    lines,
    flush: true,
  );
}

// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

Future<void> _generateDependenciesFile({required String dependenciesFilePath}) async {
  final file = File(dependenciesFilePath);
  final exists = await file.exists();
  if (!exists) {
    final lines = [
      "// TODO: Put your dependencies here for _parent.g.dart",
      "",
      "// /* e.g. */ export 'package:image_picker/image_picker.dart';",
    ].join("\n");
    await file.create(recursive: true);
    await file.writeAsString(
      lines,
      flush: true,
    );
  }
}
