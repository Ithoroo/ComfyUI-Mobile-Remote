import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

class SshService {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool isWindows;
  final String linuxComfyPath;
  final String linuxPythonCmd;
  final String linuxGpu;
  final String windowsComfyPath; // empty = use default

  // Windows paths (use PowerShell env vars)
  static const _winLogPath  = r'$env:USERPROFILE\comfyui.log';
  static const _winComfyExe = r'$env:LOCALAPPDATA\Programs\ComfyUI\ComfyUI.exe';

  // Linux log path
  static const _linuxLogPath = '~/comfyui.log';

  SshService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.isWindows = true,
    this.linuxComfyPath = '~/ComfyUI',
    this.linuxPythonCmd = 'python',
    this.linuxGpu = 'nvidia',
    this.windowsComfyPath = '',
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

  /// Launch ComfyUI — works on Windows (WMI) and Linux (nohup).
  Future<bool> startComfy() async {
    try {
      final client = await _connect();
      final gpuArgs = linuxGpu == 'amd'
          ? 'HSA_OVERRIDE_GFX_VERSION=11.0.0 '
          : linuxGpu == 'cpu' ? '' : '';
      final extraArgs = linuxGpu == 'cpu' ? ' --cpu' : '';
      // Use custom path if set, otherwise default AppData location
      final comfyExe = windowsComfyPath.isNotEmpty
          ? windowsComfyPath
          : 'C:\\Users\\$username\\AppData\\Local\\Programs\\ComfyUI\\ComfyUI.exe';
      final logPath  = isWindows
          ? 'C:\\Users\\$username\\comfyui.log'
          : _linuxLogPath;
      final cmd = isWindows
          ? 'powershell -Command "\$wmi = [wmiclass]\'Win32_Process\'; \$wmi.Create(\'cmd.exe /c \\\"$comfyExe\\\" > $logPath 2>&1\')"'
          : 'nohup bash -c "cd $linuxComfyPath && ${gpuArgs}$linuxPythonCmd main.py --listen 0.0.0.0$extraArgs" > $_linuxLogPath 2>&1 &';
      print('[SSH] startComfy cmd: $cmd');
      final session = await client.execute(cmd);
      await session.stdout.drain();
      await session.stderr.drain();
      await session.done;
      client.close();
      await client.done;
      return true;
    } catch (e) {
      print('[SSH] startComfy error: $e');
      return false;
    }
  }

  /// Read the last N lines of the ComfyUI log file.
  Future<String> readLogs({int lines = 50}) async {
    try {
      final client = await _connect();
      final logPath = isWindows
          ? 'C:\\Users\\$username\\comfyui.log'
          : _linuxLogPath;
      final cmd = isWindows
          ? 'powershell -Command "Get-Content \'$logPath\' -Tail $lines"'
          : 'tail -n $lines $_linuxLogPath';
      final session = await client.execute(cmd);
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
      final cmd = isWindows
          ? 'taskkill /F /IM ComfyUI.exe /T'
          : 'pkill -f "python main.py"';
      final session = await client.execute(cmd);
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
    final cmd = isWindows ? 'shutdown /s /t 0' : 'sudo shutdown -h now';
    final session = await client.execute(cmd);
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