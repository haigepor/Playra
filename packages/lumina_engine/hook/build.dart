import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) => build(args, (input, output) async {
  if (!input.config.buildCodeAssets) return;
  final code = input.config.code;
  final armCore =
      code.targetOS == OS.android &&
      code.targetArchitecture == Architecture.arm64;
  if (!armCore) {
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'core_shim',
        linkMode: LookupInProcess(),
      ),
    );
  }
  // 未交付的目标只保留符号描述；应用不会在这些平台登记 Lumina。
  final name = switch ((code.targetOS, code.targetArchitecture)) {
    (OS.windows, Architecture.x64) => 'fuse_core.dll',
    (OS.android, Architecture.x64) => 'liblumafuse_android_x64.so',
    (OS.android, Architecture.arm64) => 'liblumafuse_android_arm64.so',
    _ => null,
  };
  if (name == null) {
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'engine',
        linkMode: LookupInProcess(),
      ),
    );
    return;
  }
  final root = input.packageRoot.resolve('native/');
  final receipt = File.fromUri(input.packageRoot.resolve('inputs.json'));
  final manifest = jsonDecode(await receipt.readAsString()) as Map;
  for (final entry in (manifest['assets'] as Map).entries) {
    final asset = File.fromUri(
      input.packageRoot.resolve('../../assets/lumina_private/${entry.key}'),
    );
    if (sha256.convert(await asset.readAsBytes()).toString() != entry.value) {
      throw StateError('Lumina asset integrity mismatch: ${entry.key}');
    }
    output.dependencies.add(asset.uri);
  }
  final source = File.fromUri(root.resolve(name));
  final bytes = await source.readAsBytes();
  if (sha256.convert(bytes).toString() != manifest['files'][name]) {
    throw StateError('Lumina native input integrity mismatch: $name');
  }
  final target = File.fromUri(
    input.outputDirectory.resolve(
      code.targetOS == OS.windows ? 'lumafuse.dll' : 'liblumafuse.so',
    ),
  );
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes, flush: true);
  output.dependencies.addAll([receipt.uri, source.uri]);
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'engine',
      linkMode: DynamicLoadingBundled(),
      file: target.uri,
    ),
  );
  if (armCore) {
    final vendor = File.fromUri(root.resolve('libcore_android_arm64.so'));
    if (sha256.convert(await vendor.readAsBytes()).toString() !=
        manifest['files']['libcore_android_arm64.so']) {
      throw StateError('Lumina core vendor input integrity mismatch');
    }
    final vendorTarget = File.fromUri(
      input.outputDirectory.resolve('liblumina_core_vendor.so'),
    );
    await vendor.copy(vendorTarget.path);
    output.dependencies.add(vendor.uri);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'core_vendor',
        linkMode: DynamicLoadingBundled(),
        file: vendorTarget.uri,
      ),
    );
    // NDK 编译本项目的 C 适配层；供应商库仅从只读打包目录 dlopen。
    await CBuilder.library(
      name: 'lumina_core_shim',
      assetName: 'core_shim',
      sources: ['src/lumina_core_shim.c'],
      includes: ['include'],
      libraries: ['dl'],
      flags: ['-Wl,-z,max-page-size=16384'],
    ).run(input: input, output: output);
  }
});
