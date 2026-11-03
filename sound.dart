import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'sounds_data.dart';

/// Shaxmat ovoz effektlari: yurish, olish, shoh, rokirovka, o'yin oxiri.
/// Ovozlar dasturga o'rnatilgan; birinchi ishlatishda vaqtinchalik
/// papkaga yoziladi va qurilma pleyeri orqali chalinadi.
class Sfx {
  Sfx._();
  static final Sfx instance = Sfx._();

  bool enabled = true;

  final Map<String, String> _paths = {};
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  Future<void>? _init;

  Future<void> _prepare() async {
    try {
      final sep = Platform.pathSeparator;
      final dir = Directory('${Directory.systemTemp.path}${sep}achess_sfx_v1');
      await dir.create(recursive: true);
      for (final e in kSoundData.entries) {
        final f = File('${dir.path}$sep${e.key}.wav');
        final bytes = base64Decode(e.value);
        if (!await f.exists() || await f.length() != bytes.length) {
          await f.writeAsBytes(bytes, flush: true);
        }
        _paths[e.key] = f.path;
      }
      for (var i = 0; i < 4; i++) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
    } catch (_) {
      _paths.clear();
    }
  }

  /// Ovozni oldindan tayyorlaydi (ilova ochilganda chaqiriladi).
  Future<void> init() => _init ??= _prepare();

  Future<void> play(String name, {Duration delay = Duration.zero}) async {
    if (!enabled) return;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!enabled) return;
      await init();
      final key = name == 'end' ? 'win' : name;
      final path = _paths[key];
      if (path == null || _pool.isEmpty) return;
      final pl = _pool[_next++ % _pool.length];
      await pl.stop();
      await pl.play(DeviceFileSource(path), volume: 0.85);
    } catch (_) {
      // Ovoz ishlamasa, o'yin to'xtamaydi.
    }
  }

  /// Yurish yozuvi (SAN) bo'yicha mos ovozni chaladi.
  void playSan(String san) {
    String name = 'move';
    if (san.contains('=')) {
      name = 'promote';
    } else if (san.endsWith('+') || san.endsWith('#')) {
      name = 'check';
    } else if (san.startsWith('O-O')) {
      name = 'castle';
    } else if (san.contains('x')) {
      name = 'capture';
    }
    play(name);
  }
}
