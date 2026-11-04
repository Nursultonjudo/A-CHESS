import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Windows: ilova birinchi marta ishga tushganda ish stolida "A-CHESS" yorlig'ini yaratadi.
/// Ilova boshqa joyga ko'chirilsa, yorliq yangi manzilga yangilanadi.
Future<void> ensureDesktopShortcut() async {
  if (!Platform.isWindows) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final exe = Platform.resolvedExecutable;
    if (prefs.getString('shortcutFor') == exe) return;
    final dir = File(exe).parent.path;
    const script = r'''
$d = [Environment]::GetFolderPath('Desktop')
$w = New-Object -ComObject WScript.Shell
$l = $w.CreateShortcut((Join-Path $d 'A-CHESS.lnk'))
$l.TargetPath = $env:A_EXE
$l.WorkingDirectory = $env:A_DIR
$l.IconLocation = $env:A_EXE + ',0'
$l.Description = 'A-CHESS'
$l.Save()
''';
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      environment: {'A_EXE': exe, 'A_DIR': dir},
    );
    if (r.exitCode == 0) await prefs.setString('shortcutFor', exe);
  } catch (_) {
    // Yorliq yaratilmasa ham ilova ishlayveradi.
  }
}
