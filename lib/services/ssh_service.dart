import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

class SshService {
  final String host;
  final int port;
  final String username;
  final String password;

  static const _logPath = r'C:\Users\trusz\comfyui.log';
  static const _comfyExe = r'C:\Users\trusz\AppData\Local\Programs\ComfyUI\ComfyUI.exe';

  SshService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  Future<SSHClient> _connect() async {
    final socket = await SSHSocket.connect(host, port)
        .timeout(const Duration(seconds: 5));
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    await client.authenticated;
    return client;
  }

  Future<bool> isReachable() async {
    try {
      final client = await _connect();
      client.close();
      await client.done;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Check if ComfyUI is running by pinging its HTTP port.
  Future<bool> isComfyRunning(String comfyUrl) async {
    try {
      final uri = Uri.parse(comfyUrl);
      final socket = await Socket.connect(
        uri.host,
        uri.port > 0 ? uri.port : 8188,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Launch ComfyUI via WMI with log capture.
  /// WMI creates the process outside the SSH session tree so it
  /// survives when the SSH connection closes.
  Future<bool> startComfy() async {
    try {
      final client = await _connect();
      final session = await client.execute(
        'powershell -Command "\$wmi = [wmiclass]\'Win32_Process\'; \$wmi.Create(\'cmd.exe /c \\\"$_comfyExe\\\" > $_logPath 2>&1\')"',
      );
      await session.stdout.drain();
      await session.stderr.drain();
      await session.done;
      client.close();
      await client.done;
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('[SSH] startComfy error: $e');
      return false;
    }
  }

  /// Read the last N lines of the ComfyUI log file.
  Future<String> readLogs({int lines = 50}) async {
    try {
      final client = await _connect();
      final session = await client.execute(
        'powershell -Command "Get-Content \'$_logPath\' -Tail $lines"',
      );
      final output = await session.stdout
          .map((bytes) => String.fromCharCodes(bytes))
          .join();
      await session.done;
      client.close();
      await client.done;
      return output.isEmpty ? 'Log file is empty.' : output;
    } catch (e) {
      return 'Failed to read logs: $e';
    }
  }

  /// Kill all ComfyUI processes.
  Future<bool> killComfy() async {
    try {
      final client = await _connect();
      final session = await client.execute(
        'taskkill /F /IM ComfyUI.exe /T',
      );
      await session.stdout.drain();
      await session.done;
      client.close();
      await client.done;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> shutdownPC() async {
    final client = await _connect();
    final session = await client.execute('shutdown /s /t 0');
    await session.done;
    client.close();
    await client.done;
  }

  Future<bool> testConnection() async {
    try {
      final client = await _connect();
      client.close();
      await client.done;
      return true;
    } catch (_) {
      return false;
    }
  }
}