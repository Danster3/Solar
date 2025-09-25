import 'dart:io';

class TokenStoreImpl {
  final String _path;
  TokenStoreImpl([this._path = 'sems_token.json']);

  Future<String?> read() async {
    try {
      final f = File(_path);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String value) async {
    final f = File(_path);
    await f.writeAsString(value);
  }

  Future<void> delete() async {
    try {
      final f = File(_path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
