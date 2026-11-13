import 'dart:async';
import 'dart:convert';

import '../domain/lang.dart';
import '../live/session_pipe.dart';
import '../openai/realtime_translate.dart';
import 'demo_script.dart';

/// Opens translation sessions against [DemoTranslateServer] instead of
/// OpenAI. The real client code (protocol, captions, reconnects) runs.
SessionOpener demoOpener({double speed = 1}) => (config) => TranslateSession.open(
      apiKey: 'demo',
      config: config,
      connector: (url, headers) async => DemoTranslateServer(speed: speed),
    );

/// A scripted stand-in for `gpt-realtime-translate` speaking the wire
/// format of OpenAI's realtime translation sessions.
///
/// - The meeting session (far-field noise reduction) plays [demoMeeting]:
///   source text chunk by chunk, then the translation into the session's
///   output language, then a short tone as "translated speech". A line
///   already in the output language gets no translation, like the model.
/// - The "Phát biểu" session (near-field) answers with [demoReply] after
///   about a second of audio, then a 1.2 s tone, to test the loudspeaker.
class DemoTranslateServer implements WsLink {
  DemoTranslateServer({this.speed = 1});

  /// Below 1 plays faster (tests).
  final double speed;

  final _out = StreamController<String>();
  final _timers = <Timer>[];
  final _clock = Stopwatch()..start();
  Lang _target = Lang.vi;
  bool _reply = false;
  bool _started = false;
  bool _answered = false;
  int _audioBytes = 0;

  @override
  Stream<String> get messages => _out.stream;

  @override
  void send(String text) {
    final Map<String, Object?> e;
    try {
      e = (jsonDecode(text) as Map).cast<String, Object?>();
    } on Object {
      return;
    }
    switch (e['type']) {
      case 'session.update':
        final audio = ((e['session'] as Map?)?['audio'] as Map?) ?? const {};
        final lang = Lang.fromCode((audio['output'] as Map?)?['language'] as String?);
        if (lang != null) _target = lang;
        final noise = ((audio['input'] as Map?)?['noise_reduction'] as Map?)?['type'];
        if (!_started) {
          _started = true;
          _reply = noise == 'near_field';
          _emit({
            'type': 'session.created',
            'session': {'id': 'demo_${DateTime.now().millisecondsSinceEpoch}', 'type': 'translation'},
          });
          if (!_reply) _playMeeting();
        }
      case 'session.input_audio_buffer.append':
        _audioBytes += (e['audio'] as String? ?? '').length * 3 ~/ 4;
        if (_reply && !_answered && _audioBytes >= pcmSampleRate * 2) {
          _answered = true;
          _playLine(demoReply, Duration.zero, tone: const Duration(milliseconds: 1200), frequency: 440);
        }
      case 'session.close':
        _cancel();
        _after(const Duration(milliseconds: 50), () => _emit({'type': 'session.closed'}));
    }
  }

  void _playMeeting() => _nextLine(0, const Duration(milliseconds: 1200));

  /// Lines are scheduled one at a time, so a change of "Dịch sang" applies
  /// from the next line on.
  void _nextLine(int i, Duration wait) {
    if (i >= demoMeeting.length) return;
    _after(wait, () {
      final length = _playLine(demoMeeting[i], Duration.zero);
      _nextLine(i + 1, length + const Duration(milliseconds: 1500));
    });
  }

  /// Schedules [line] from [start]; returns when it ends.
  Duration _playLine(
    DemoLine line,
    Duration start, {
    Duration tone = const Duration(milliseconds: 350),
    double frequency = 880,
  }) {
    var t = start;
    for (final c in demoChunks(line.said)) {
      _after(t, () => _emit({'type': 'session.input_transcript.delta', 'delta': c, 'elapsed_ms': _elapsed()}));
      t += const Duration(milliseconds: 140);
    }
    if (line.spoken == _target) return t;
    t += const Duration(milliseconds: 700);
    for (final c in demoChunks(line.inLang(_target))) {
      _after(t, () => _emit({'type': 'session.output_transcript.delta', 'delta': c, 'elapsed_ms': _elapsed()}));
      t += const Duration(milliseconds: 100);
    }
    final pcm = demoTone(length: tone, frequency: frequency, volume: _reply ? 0.35 : 0.15);
    const chunk = chunkBytes;
    for (var off = 0; off < pcm.length; off += chunk) {
      final end = off + chunk > pcm.length ? pcm.length : off + chunk;
      final piece = pcm.sublist(off, end);
      _after(t, () => _emit({
            'type': 'session.output_audio.delta',
            'delta': base64Encode(piece),
            'sample_rate': pcmSampleRate,
            'channels': 1,
            'format': 'pcm16',
          }));
      t += const Duration(milliseconds: 150);
    }
    return t;
  }

  int _elapsed() => _clock.elapsedMilliseconds;

  void _after(Duration d, void Function() f) {
    _timers.add(Timer(Duration(microseconds: (d.inMicroseconds * speed).round()), f));
  }

  void _emit(Map<String, Object?> e) {
    if (!_out.isClosed) _out.add(jsonEncode(e));
  }

  void _cancel() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  @override
  Future<void> close() async {
    _cancel();
    if (!_out.isClosed) await _out.close();
  }
}
