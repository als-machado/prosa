import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SshService {
  Future<Directory> get _sshDir async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/ssh');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<String> get privateKeyPath async {
    final dir = await _sshDir;
    return '${dir.path}/id_ed25519';
  }

  Future<String> get publicKeyPath async {
    final dir = await _sshDir;
    return '${dir.path}/id_ed25519.pub';
  }

  Future<bool> get hasKeyPair async {
    final priv = File(await privateKeyPath);
    return priv.existsSync();
  }

  Future<SshKeyPair> generateKeyPair({String comment = 'prosa-key'}) async {
    final privPath = await privateKeyPath;
    final privFile = File(privPath);
    if (privFile.existsSync()) privFile.deleteSync();

    final result = await Process.run('ssh-keygen', [
      '-t', 'ed25519',
      '-f', privPath,
      '-N', '',
      '-C', comment,
    ]);

    if (result.exitCode != 0) {
      throw Exception('Falha ao gerar chave SSH: ${result.stderr}');
    }

    final pubPath = await publicKeyPath;
    final publicKey = await File(pubPath).readAsString();
    return SshKeyPair(privatePath: privPath, publicKey: publicKey.trim());
  }

  Future<String?> readPublicKey() async {
    final path = await publicKeyPath;
    final file = File(path);
    if (!file.existsSync()) return null;
    return (await file.readAsString()).trim();
  }

  Future<void> copyPublicKeyToClipboard() async {
    final key = await readPublicKey();
    if (key == null) throw Exception('Nenhuma chave pública encontrada');
    await Clipboard.setData(ClipboardData(text: key));
  }

  Future<void> importPrivateKey(String content) async {
    final path = await privateKeyPath;
    final file = File(path);
    // Cria vazio e restringe permissões ANTES de escrever a chave — escrever
    // primeiro deixaria o conteúdo legível (0644) até o chmod rodar.
    await file.writeAsString('');
    await Process.run('chmod', ['600', path]);
    await file.writeAsString(content);
  }

  Future<bool> testConnection(String host, String user) async {
    final privPath = await privateKeyPath;
    final result = await Process.run('ssh', [
      '-i', privPath,
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'BatchMode=yes',
      '-T',
      '$user@$host',
    ]);
    return result.exitCode == 1;
  }
}

class SshKeyPair {
  final String privatePath;
  final String publicKey;
  const SshKeyPair({required this.privatePath, required this.publicKey});
}
