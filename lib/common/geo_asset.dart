import 'dart:io';

Future<void> ensureGeoAsset(File target, Future<void> Function(File) extract) async {
  if (await target.exists() && await target.length() > 0) return;
  await target.parent.create(recursive: true);
  final temporary = await target.parent.createTemp('.geo-');
  try {
    final staged = File('${temporary.path}/asset');
    await extract(staged);
    if (!await staged.exists() || await staged.length() == 0) {
      throw const FormatException('Empty geographic data asset');
    }
    await staged.rename(target.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}
