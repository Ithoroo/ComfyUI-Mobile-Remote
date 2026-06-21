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
  final String windowsInstallType; // 'desktop', 'portable', 'custom'
  final String desktopSourcePath;
  final String desktopDataPath;

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
    this.windowsInstallType = 'desktop',
    this.desktopSourcePath = '',
    this.desktopDataPath = '',
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
      // Resolve the Windows executable path based on install type
      String comfyExe;
      bool isDesktop = false;
      if (windowsComfyPath.isNotEmpty) {
        comfyExe = windowsComfyPath; // custom path
      } else if (windowsInstallType == 'desktop') {
        comfyExe = 'C:\\Users\\$username\\AppData\\Local\\Programs\\ComfyUI\\Comfy Desktop.exe';
        isDesktop = true;
      } else {
        comfyExe = 'C:\\Users\\$username\\AppData\\Local\\Programs\\ComfyUI\\ComfyUI.exe';
      }
      final logPath  = isWindows
          ? 'C:\\Users\\$username\\comfyui.log'
          : _linuxLogPath;
      final String cmd;
      if (!isWindows) {
        cmd = 'nohup bash -c "cd $linuxComfyPath && ${gpuArgs}$linuxPythonCmd main.py --listen 0.0.0.0$extraArgs" > $_linuxLogPath 2>&1 &';
      } else if (isDesktop) {
        // ComfyUI Desktop: run the server directly via venv python.
        // Use $env:USERPROFILE so the path resolves to the real Windows
        // profile folder (SSH username may differ, e.g. an email login).
        // Relative-to-profile paths (defaults can be overridden in settings):
        final dataRel = desktopDataPath.isNotEmpty
            ? desktopDataPath
            : r'Documents\ComfyUI';
        final srcRel = desktopSourcePath.isNotEmpty
            ? desktopSourcePath
            : r'ComfyUI-Installs\ComfyUI\ComfyUI';
        // Build a PowerShell script that resolves $env:USERPROFILE first,
        // then launches via WMI so it survives the SSH session closing.
        cmd = 'powershell -Command "'
            '\$up = \$env:USERPROFILE; '
            '\$data = Join-Path \$up \'$dataRel\'; '
            '\$src = Join-Path \$up \'$srcRel\'; '
            '\$py = Join-Path \$data \'.venv\\Scripts\\python.exe\'; '
            '\$log = Join-Path \$up \'comfyui.log\'; '
            '\$main = Join-Path \$src \'main.py\'; '
            '\$a = \'-s \"\' + \$main + \'\" --base-directory \"\' + \$data + \'\" --user-directory \"\' + (Join-Path \$data \'user\') + \'\" --listen 0.0.0.0 --port 8000 --enable-manager --output-directory \"\' + (Join-Path \$data \'output\') + \'\"\'; '
            '\$wmi = [wmiclass]\'Win32_Process\'; '
            '\$wmi.Create(\'cmd.exe /c \"\' + \$py + \'\" \' + \$a + \' > \"\' + \$log + \'\" 2>&1\')"';
      } else {
        // Portable .exe — WMI with log capture, survives SSH disconnect
        cmd = 'powershell -Command "\$wmi = [wmiclass]\'Win32_Process\'; \$wmi.Create(\'cmd.exe /c \\\"$comfyExe\\\" > $logPath 2>&1\')"';
      }
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
      final String cmd;
      if (!isWindows) {
        cmd = 'pkill -f "python main.py"';
      } else if (windowsInstallType == 'desktop') {
        // Desktop runs as python.exe — kill only the one running main.py,
        // not every python process on the machine
        cmd = 'powershell -Command "Get-CimInstance Win32_Process | '
            'Where-Object { \$_.CommandLine -like \'*ComfyUI*main.py*\' } | '
            'ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }"';
      } else {
        cmd = 'taskkill /F /IM ComfyUI.exe /T';
      }
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