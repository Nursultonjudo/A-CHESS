import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:ffi/ffi.dart';

import 'sounds_data.dart';

/// Shaxmat ovoz effektlari: yurish, olish, shoh, rokirovka, o'yin oxiri.
///
/// Windows: tizimning winmm.dll (PlaySound) orqali xotiradan chalinadi —
/// qo'shimcha plagin kerak emas, ovoz balandligi namunalarga qo'llanadi.
/// Android: audioplayers orqali chalinadi.
class Sfx {
  Sfx._();
  static final Sfx instance = Sfx._();

  bool enabled = true;
  double volume = 0.8; // 0..1

  // ---- Windows ----
  static const int _sndAsync = 0x1;
  static const int _sndNoDefault = 0x2;
  static const int _sndMemory = 0x4;
  int Function(ffi.Pointer<ffi.Void>, int, int)? _playSound;
  final Map<String, ffi.Pointer<ffi.Uint8>> _native = {};
  double _builtVolume = -1;

  // ---- Android va boshqalar ----
  final Map<String, String> _paths = {};
  final List<AudioPlayer> _pool = [];
  int _next = 0;

  Future<void>? _init;

  Future<void> _prepare() async {
    if (Platform.isWindows) {
      try {
        final lib = ffi.DynamicLibrary.open('winmm.dll');
        _playSound = lib.lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.IntPtr, ffi.Uint32),
            int Function(ffi.Pointer<ffi.Void>, int, int)>('PlaySoundW');
        _rebuildNative();
      } catch (_) {
        _playSound = null;
      }
      return;
    }
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

  /// Windows: balandlikka moslangan WAV xotirasini quradi.
  void _rebuildNative() {
    final ps = _playSound;
    if (ps == null) return;
    ps(ffi.nullptr, 0, 0); // chalinayotgan ovozni to'xtatish
    for (final p in _native.values) {
      malloc.free(p);
    }
    _native.clear();
    for (final e in kSoundData.entries) {
      final src = base64Decode(e.value);
      final out = Uint8List.fromList(src);
      final bd = ByteData.sublistView(out);
      // 44 baytli sarlavhadan keyin 16 bitli PCM namunalar
      for (var i = 44; i + 1 < out.length; i += 2) {
        final v = (bd.getInt16(i, Endian.little) * volume).round();
        bd.setInt16(i, v.clamp(-32768, 32767), Endian.little);
      }
      final ptr = malloc<ffi.Uint8>(out.length);
      ptr.asTypedList(out.length).setAll(0, out);
      _native[e.key] = ptr;
    }
    _builtVolume = volume;
  }

  Future<void> play(String name, {Duration delay = Duration.zero}) async {
    if (!enabled) return;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!enabled) return;
      await init();
      final key = name == 'end' ? 'win' : name;
      final ps = _playSound;
      if (Platform.isWindows) {
        if (ps == null) return;
        if ((volume - _builtVolume).abs() > 0.001) _rebuildNative();
        final ptr = _native[key];
        if (ptr == null) return;
        ps(ptr.cast<ffi.Void>(), 0, _sndMemory | _sndAsync | _sndNoDefault);
        return;
      }
      final path = _paths[key];
      if (path == null || _pool.isEmpty) return;
      final pl = _pool[_next++ % _pool.length];
      await pl.stop();
      await pl.play(DeviceFileSource(path), volume: volume);
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
