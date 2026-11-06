import 'dart:io';

/// Windows: ilova har ishga tushganda ish stolida (va Start menyusida) "A-CHESS"
/// yorlig'i borligini tekshiradi; yo'q bo'lsa yoki boshqa joyga qaragan bo'lsa,
/// qayta yaratadi. (Oldingi versiya faqat bir marta urinardi va o'chirilgan
/// yorliqni qayta tiklamasdi.)
Future<void> ensureDesktopShortcut() async {
  if (!Platform.isWindows) return;
  try {
    final exe = Platform.resolvedExecutable;
    final dir = File(exe).parent.path;
    const script = r'''
$w = New-Object -ComObject WScript.Shell
$places = @(
  [Environment]::GetFolderPath('Desktop'),
  (Join-Path ([Environment]::GetFolderPath('Programs')) '')
)
foreach ($p in $places) {
  if (-not $p -or -not (Test-Path $p)) { continue }
  $f = Join-Path $p 'A-CHESS.lnk'
  $ok = $false
  if (Test-Path $f) {
    try { $ok = ($w.CreateShortcut($f).TargetPath -eq $env:A_EXE) } catch {}
  }
  if (-not $ok) {
    $l = $w.CreateShortcut($f)
    $l.TargetPath = $env:A_EXE
    $l.WorkingDirectory = $env:A_DIR
    $l.IconLocation = $env:A_EXE + ',0'
    $l.Description = 'A-CHESS'
    $l.Save()
  }
}
''';
    await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      environment: {'A_EXE': exe, 'A_DIR': dir},
    );
  } catch (_) {
    // Yorliq yaratilmasa ham ilova ishlayveradi.
  }
}
