import 'dart:async';
import 'package:flutter/foundation.dart';

import '../domain/caption_assembler.dart';
import '../domain/lang.dart';
import '../domain/records.dart';
import '../domain/segmenter.dart';
import '../openai/openai_error.dart';
import '../openai/realtime_translate.dart';
import '../openai/text_ai.dart';
import '../storage/library_store.dart';
import 'audio_ports.dart';
import 'session_pipe.dart';

enum LiveState { idle, starting, live, pausing, paused, finishing, finished, failed }

/// Timings, injectable so tests run fast.
class LiveTimings {
  const LiveTimings({
    this.settleAfter = const Duration(milliseconds: 2500),
    this.tick = const Duration(milliseconds: 250),
    this.rolloverAt = const Duration(minutes: 50),
    this.reconnectDelays = const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)],
    this.drainMinWait = const Duration(milliseconds: 800),
    this.drainQuiet = const Duration(milliseconds: 1500),
    this.drainMaxWait = const Duration(seconds: 6),
  });

  /// Pause in both text streams after which pending text is settled.
  final Duration settleAfter;
  final Duration tick;

  /// Session audio after which a fresh session takes over. OpenAI caps
  /// realtime sessions at 60 minutes.
  final Duration rolloverAt;
  final List<Duration> reconnectDelays;
  final Duration drainMinWait;
  final Duration drainQuiet;
  final Duration drainMaxWait;
}

/// Runs a live meeting: microphone → translation session → captions,
/// with pause/resume, read-aloud, reconnects and session rollover.
class MeetingController extends ChangeNotifier {
  MeetingController({
    required SessionOpener opener,
    required this.mic,
    required this.speaker,
    required this.store,
    required Lang target,
    this.title = '',
    this.context = const MeetingContext(),
    this._readAloud = false,
    this.textAi,
    this.awake = const NoScreenAwake(),
    this.background = const NoBackgroundRecording(),
    this.timings = const LiveTimings(),
    this.onAudioBilled,
    DateTime Function()? clock,
  })  : _target = target,
        _now = clock ?? DateTime.now,
        assembler = CaptionAssembler(target: target) {
    _pipe = SessionPipe(opener: opener, onEvent: _onEvent, clock: _now);
  }

  final MicSource mic;

  final PcmSink speaker;
  final LibraryStore store;
  final String title;
  final MeetingContext context;

  /// Used to re-translate sentences that contain a glossary term.
  final TextAi? textAi;
  final ScreenAwake awake;

  /// Keeps the microphone alive with the screen off.
  final BackgroundRecording background;

  final LiveTimings timings;
  final void Function(Duration audio)? onAudioBilled;
  final DateTime Function() _now;

  final CaptionAssembler assembler;
  late final SessionPipe _pipe;

  LiveState _state = LiveState.idle;
  LiveState get state => _state;

  Lang _target;
  Lang get target => _target;

  bool _readAloud;
  bool get readAloud => _readAloud;

  /// Last problem worth showing; cleared when things recover.
  String? notice;

  DateTime? _startedAt;
  int _recordedBytes = 0;
  DateTime _lastText = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<Uint8List>? _micSub;
  Timer? _ticker;
  bool _switching = false;
  String _shownClock = '';
  int _reconnectAttempt = 0;
  final _glossaryChecked = Set<Sentence>.identity();
  LibraryItem? saved;

  /// Questions asked during the meeting ("Hỏi nhanh"), saved with it.
  final List<QaPair> liveQa = [];
  bool asking = false;

  Duration get recorded =>
      Duration(microseconds: _recordedBytes * 1000000 ~/ (pcmSampleRate * 2));

  List<Sentence> get sentences => assembler.committed;
  String get liveSource => assembler.liveSource;
  String get liveTranslation => assembler.liveTranslation;
  bool get isRecording => _state == LiveState.live;

  Future<void> start() async {
    if (_state != LiveState.idle) return;
    _setState(LiveState.starting);
    try {
      if (!await mic.ensurePermission()) {
        _fail('Ứng dụng cần quyền dùng micro để ghi cuộc họp.');
        return;
      }
      _startedAt = _now();
      await _startMic();
      await _attachNew();
      _ticker = Timer.periodic(timings.tick, (_) => _onTick());
      await awake.set(true);
      await _showBackground();
      _setState(LiveState.live);
    } on Object catch (e) {
      await _stopMic();
      if (_state != LiveState.finished) _fail(_describe(e));
    }
  }

  Future<void> pause() async {
    if (_state != LiveState.live) return;
    _setState(LiveState.pausing);
    await _stopMic();
    await _drainActive();
    assembler.settle();
    _afterTextChange();
    _pipe.clearBuffer();
    await speaker.stop();
    await awake.set(false);
    await background.stop();
    _setState(LiveState.paused);
  }

  Future<void> resume() async {
    if (_state != LiveState.paused) return;
    _setState(LiveState.starting);
    try {
      await _startMic();
      await _attachNew();
      await awake.set(true);
      await _showBackground();
      _setState(LiveState.live);
    } on Object catch (e) {
      await _stopMic();
      notice = _describe(e);
      _setState(LiveState.paused);
    }
  }

  /// Stops, saves to the Library and returns the saved item.
  Future<LibraryItem?> finish() async {
    if (_state == LiveState.finished) return saved;
    if (_state == LiveState.live) await pause();
    if (_state != LiveState.paused && _state != LiveState.failed) return null;
    _setState(LiveState.finishing);
    _ticker?.cancel();
    assembler.settle();
    LibraryItem? item;
    if (assembler.committed.isNotEmpty) {
      item = snapshot();
      await store.save(item);
    }
    saved = item;
    await background.stop();
    await _pipe.dispose();
    _setState(LiveState.finished);
    return item;
  }

  /// Stops without saving.
  Future<void> discard() async {
    _ticker?.cancel();
    await _stopMic();
    await _pipe.dispose();
    await speaker.stop();
    await awake.set(false);
    await background.stop();
    _setState(LiveState.finished);
  }

  /// The meeting so far as a Library item (what [finish] saves).
  LibraryItem snapshot() {
    final started = _startedAt ?? _now();
    return LibraryItem(
      id: newItemId(started),
      kind: ItemKind.meeting,
      title: title.trim().isEmpty ? _defaultTitle(started) : title.trim(),
      createdAt: started,
      duration: recorded,
      targetLang: _target,
      context: context,
      sentences: List.of(assembler.committed),
      qa: List.of(liveQa),
    );
  }

  /// "Hỏi nhanh": answers [question] from what has been said so far.
  Future<QaPair> ask(String question) async {
    final ai = textAi;
    if (ai == null) throw StateError('no text model');
    asking = true;
    notifyListeners();
    try {
      final qa = await ai.ask(snapshot(), question);
      liveQa.add(qa);
      return qa;
    } finally {
      asking = false;
      notifyListeners();
    }
  }

  /// Flags or unflags the sentence at [index] of [sentences].
  void toggleMark(int index) {
    final list = assembler.committed;
    if (index < 0 || index >= list.length) return;
    final s = list[index];
    final next = s.copyWith(marked: !s.marked);
    _glossaryChecked.add(next);
    list[index] = next;
    notifyListeners();
  }

  void setReadAloud(bool on) {
    _readAloud = on;
    if (!on) unawaited(speaker.stop());
    notifyListeners();
  }

  /// Changes "Dịch sang" for the rest of the meeting.
  void setTarget(Lang lang) {
    if (lang == _target) return;
    assembler.settle();
    _target = lang;
    assembler.target = lang;
    _pipe.active?.updateTarget(lang);
    _afterTextChange();
    notifyListeners();
  }

  // --- internals ---

  Future<void> _startMic() async {
    final stream = await mic.start();
    _micSub = stream.listen((pcm) {
      if (_state != LiveState.live && _state != LiveState.starting) return;
      _recordedBytes += pcm.length;
      _pipe.push(pcm);
    });
  }

  Future<void> _stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    await mic.stop();
  }

  TranslateConfig _config() => TranslateConfig(target: _target);

  /// Opens a session that takes the audio from now on. Audio recorded while
  /// it connects is buffered and sent first.
  Future<void> _attachNew() async {
    final bufferedBefore = Duration(
      microseconds: _pipe.bufferedBytes * 1000000 ~/ (pcmSampleRate * 2),
    );
    final offset = recorded - bufferedBefore;
    final s = await _pipe.attach(_config());
    // Text from the new session is timed from the start of its audio.
    assembler.offset = offset < Duration.zero ? Duration.zero : offset;
    _reconnectAttempt = 0;
    notice = _pipe.droppedAudio ? 'Mất một đoạn âm thanh khi kết nối lại.' : null;
    _pipe.droppedAudio = false;
    assert(s.isOpen || true);
  }

  Future<void> _drainActive() async {
    final s = _pipe.detach();
    if (s == null) return;
    await _pipe.drain(
      s,
      minWait: timings.drainMinWait,
      quiet: timings.drainQuiet,
      maxWait: timings.drainMaxWait,
    );
  }

  void _onEvent(TranslateEvent e, TranslateSession from) {
    switch (e) {
      case SourceDelta(:final text, :final elapsedMs):
        _lastText = _now();
        assembler.addSource(text, elapsedMs);
        _afterTextChange();
        notifyListeners();
      case TranslationDelta(:final text):
        _lastText = _now();
        assembler.addTranslation(text);
        _afterTextChange();
        notifyListeners();
      case AudioDelta(:final pcm, :final sampleRate):
        if (_readAloud) unawaited(speaker.play(pcm, sampleRate));
      case SessionWarning(:final message):
        notice = message;
        notifyListeners();
      case SessionEnded(:final error):
        onAudioBilled?.call(from.audioSent);
        final unexpected = error != null &&
            _state == LiveState.live &&
            !_switching &&
            _pipe.lastEndedWasActive;
        if (unexpected) unawaited(_reconnect(error));
      case SessionReady():
        break;
    }
  }

  Future<void> _reconnect(Object error) async {
    _switching = true;
    try {
      while (_state == LiveState.live && _reconnectAttempt < timings.reconnectDelays.length) {
        notice = 'Mất kết nối, đang nối lại…';
        notifyListeners();
        await Future<void>.delayed(timings.reconnectDelays[_reconnectAttempt]);
        _reconnectAttempt++;
        if (_state != LiveState.live) return;
        try {
          await _attachNew();
          notifyListeners();
          return;
        } on Object catch (e) {
          if (e is OpenAiException && e.isAuth) break;
        }
      }
      if (_state == LiveState.live) {
        notice = 'Không nối lại được với OpenAI. Đã tạm dừng; bấm Tiếp tục để thử lại.';
        await pause();
      }
    } finally {
      _switching = false;
    }
  }

  void _onTick() {
    if (_state != LiveState.live) {
      notifyListeners();
      return;
    }
    final clock = formatClock(recorded);
    if (clock != _shownClock) {
      _shownClock = clock;
      unawaited(background.update(title: _noticeTitle, text: 'Đang ghi · $clock'));
    }
    if (assembler.hasPending && _now().difference(_lastText) >= timings.settleAfter) {
      assembler.settle();
      _afterTextChange();
    }
    final s = _pipe.active;
    if (s != null && !_switching && s.audioSent >= timings.rolloverAt) {
      unawaited(_rollover());
    }
    notifyListeners();
  }

  /// Hands the audio to a fresh session before the old one hits its limit.
  Future<void> _rollover() async {
    _switching = true;
    try {
      final old = _pipe.detach();
      if (old != null) {
        await _pipe.drain(old, minWait: timings.drainMinWait, quiet: timings.drainQuiet, maxWait: timings.drainMaxWait);
      }
      assembler.settle();
      _afterTextChange();
      if (_state == LiveState.live) await _attachNew();
    } on Object catch (e) {
      notice = _describe(e);
      if (_state == LiveState.live) {
        _switching = false;
        await _reconnect(e);
      }
    } finally {
      _switching = false;
    }
  }

  /// Re-translates finished sentences that contain a glossary term, since
  /// the live translation cannot take a glossary.
  void _afterTextChange() {
    final ai = textAi;
    if (ai == null || context.terms.isEmpty) return;
    final list = assembler.committed;
    for (var i = list.length - 1; i >= 0 && i >= list.length - 8; i--) {
      final s = list[i];
      if (_glossaryChecked.contains(s)) continue;
      _glossaryChecked.add(s);
      // The user's own replies go the other way; leave them as spoken.
      if (!s.hasTranslation) continue;
      final hit = context.terms.any(
        (t) => t.source.trim().isNotEmpty && s.source.toLowerCase().contains(t.source.trim().toLowerCase()),
      );
      if (!hit) continue;
      unawaited(_polish(ai, s));
    }
  }

  Future<void> _polish(TextAi ai, Sentence s) async {
    try {
      final out = await ai.translate([s.source], to: _target, context: context);
      // Found again by time and words: a mark may have replaced the object.
      final i = assembler.committed.indexWhere((x) => x.at == s.at && x.source == s.source);
      if (i < 0 || out.isEmpty || out.first.trim().isEmpty) return;
      final fixed = assembler.committed[i].copyWith(translation: out.first.trim());
      _glossaryChecked.add(fixed);
      assembler.committed[i] = fixed;
      notifyListeners();
    } on Object {
      // Keep the live translation if the correction fails.
    }
  }

  String get _noticeTitle => title.trim().isEmpty ? 'Cuộc họp' : title.trim();

  /// Shows the ongoing notification that keeps the microphone running.
  Future<void> _showBackground() async {
    _shownClock = formatClock(recorded);
    await background.start(title: _noticeTitle, text: 'Đang ghi · $_shownClock');
  }

  void _fail(String message) {
    notice = message;
    _setState(LiveState.failed);
  }

  void _setState(LiveState s) {
    _state = s;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_micSub?.cancel());
    unawaited(_pipe.dispose());
    super.dispose();
  }
}

String _describe(Object e) {
  if (e is OpenAiException) return e.userMessage;
  if (e is MissingKeyException) return e.toString();
  return 'Lỗi: $e';
}

String _defaultTitle(DateTime t) =>
    'Cuộc họp ${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String describeError(Object e) => _describe(e);
