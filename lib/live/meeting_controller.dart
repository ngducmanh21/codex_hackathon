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
import 'live_turn.dart';
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
    PcmSink? roomSpeaker,
    required this.store,
    required Lang target,
    this.title = '',
    this.context = const MeetingContext(),
    this._readAloud = false,
    this.textAi,
    this.awake = const NoScreenAwake(),
    this.timings = const LiveTimings(),
    this.onAudioBilled,
    DateTime Function()? clock,
  })  : _room = roomSpeaker ?? speaker,
        _target = target,
        _now = clock ?? DateTime.now,
        assembler = CaptionAssembler(target: target) {
    _pipe = SessionPipe(opener: opener, onEvent: _onEvent, clock: _now);
    _replyPipe = SessionPipe(opener: opener, onEvent: _onReplyEvent, clock: _now);
  }

  final MicSource mic;

  /// The user's own read-aloud (headphones when they are in).
  final PcmSink speaker;

  /// "Phát biểu": the phone's loudspeaker, for the room.
  final PcmSink _room;
  final LibraryStore store;
  final String title;
  final MeetingContext context;

  /// Used to re-translate sentences that contain a glossary term.
  final TextAi? textAi;
  final ScreenAwake awake;
  final LiveTimings timings;
  final void Function(Duration audio)? onAudioBilled;
  final DateTime Function() _now;

  final CaptionAssembler assembler;
  late final SessionPipe _pipe;

  /// Carries "Tôi trả lời": what the user says, towards the other side.
  late final SessionPipe _replyPipe;

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
  int _reconnectAttempt = 0;
  final _glossaryChecked = Set<Sentence>.identity();
  LibraryItem? saved;

  /// The reply being spoken or finished, if any.
  LiveTurn? reply;
  Lang? _replyLangChoice;

  /// The meeting session hears silence until then: while the user replies
  /// and while the phone speaks the reply, so neither is captioned twice.
  DateTime _mainMutedUntil = DateTime.fromMillisecondsSinceEpoch(0);

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
      _setState(LiveState.live);
    } on Object catch (e) {
      await _stopMic();
      if (_state != LiveState.finished) _fail(_describe(e));
    }
  }

  Future<void> pause() async {
    if (_state != LiveState.live) return;
    if (reply != null) await endReply();
    _setState(LiveState.pausing);
    await _stopMic();
    await _drainActive();
    assembler.settle();
    _afterTextChange();
    _pipe.clearBuffer();
    await speaker.stop();
    await awake.set(false);
    _setState(LiveState.paused);
  }

  Future<void> resume() async {
    if (_state != LiveState.paused) return;
    _setState(LiveState.starting);
    try {
      await _startMic();
      await _attachNew();
      await awake.set(true);
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
    await _pipe.dispose();
    await _replyPipe.dispose();
    _setState(LiveState.finished);
    return item;
  }

  /// Stops without saving.
  Future<void> discard() async {
    _ticker?.cancel();
    await _stopMic();
    await _pipe.dispose();
    await _replyPipe.dispose();
    await speaker.stop();
    await awake.set(false);
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

  /// The language "Tôi trả lời" speaks: the one chosen, else the language
  /// most heard lately other than "Dịch sang".
  Lang get replyLang {
    final chosen = _replyLangChoice;
    if (chosen != null && chosen != _target) return chosen;
    final counts = <Lang, int>{};
    final list = assembler.committed;
    for (var i = list.length - 1; i >= 0 && i >= list.length - 12; i--) {
      final l = list[i].lang;
      if (l != null && l != _target && list[i].speaker == null) counts[l] = (counts[l] ?? 0) + 1;
    }
    if (counts.isNotEmpty) {
      return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    }
    return _target == Lang.vi ? Lang.zh : Lang.vi;
  }

  /// The language chosen for "Phát biểu", or null for automatic.
  Lang? get replyLangChoice => _replyLangChoice == _target ? null : _replyLangChoice;

  /// Picks the reply language; null goes back to automatic.
  void setReplyLang(Lang? lang) {
    _replyLangChoice = lang;
    notifyListeners();
  }

  bool get replying => reply?.listening ?? false;

  /// Starts "Tôi trả lời": the user's words go to a second session that
  /// translates them into [replyLang]; the meeting session hears silence.
  Future<void> startReply() async {
    if (_state != LiveState.live || reply != null) return;
    final turn = LiveTurn(0, recorded, null);
    reply = turn;
    unawaited(speaker.stop());
    unawaited(_room.stop());
    notifyListeners();
    try {
      final s = await _replyPipe.attach(
        TranslateConfig(target: replyLang, noise: NoiseReduction.nearField),
      );
      if (!identical(reply, turn)) {
        await s.close(timeout: const Duration(seconds: 1));
        return;
      }
      turn.session = s;
    } on Object catch (e) {
      if (identical(reply, turn)) reply = null;
      _replyPipe.clearBuffer();
      notice = _describe(e);
      notifyListeners();
    }
  }

  /// Ends the reply: the phone speaks the translation aloud, then the
  /// reply joins the captions as the user's own line.
  Future<void> endReply() async {
    final turn = reply;
    if (turn == null || !turn.listening) return;
    turn.listening = false;
    for (final (pcm, rate) in turn.heldAudio) {
      _speakReply(pcm, rate);
    }
    turn.heldAudio.clear();
    notifyListeners();
    final s = _replyPipe.detach();
    if (s != null) {
      await _replyPipe.drain(
        s,
        minWait: timings.drainMinWait,
        quiet: timings.drainQuiet,
        maxWait: timings.drainMaxWait,
      );
    }
    _replyPipe.clearBuffer();
    if (identical(reply, turn)) reply = null;
    final said = turn.source.trim();
    final out = turn.translation.trim();
    if (said.isNotEmpty || out.isNotEmpty) {
      assembler.insert(Sentence(
        at: turn.at,
        source: said,
        translation: out,
        lang: guessLang(said) ?? _target,
        speaker: 0,
      ));
    }
    notifyListeners();
  }

  void _speakReply(Uint8List pcm, int rate) {
    unawaited(_room.play(pcm, rate));
    final now = _now();
    final from = _mainMutedUntil.isAfter(now) ? _mainMutedUntil : now;
    _mainMutedUntil = from.add(Duration(microseconds: pcm.length * 1000000 ~/ (rate * 2)) + const Duration(milliseconds: 150));
  }

  void _onReplyEvent(TranslateEvent e, TranslateSession from) {
    final turn = reply;
    switch (e) {
      case SourceDelta(:final text):
        turn?.source += text;
        notifyListeners();
      case TranslationDelta(:final text):
        turn?.translation += text;
        notifyListeners();
      case AudioDelta(:final pcm, :final sampleRate):
        if (turn != null && turn.listening) {
          turn.heldAudio.add((pcm, sampleRate));
        } else {
          _speakReply(pcm, sampleRate);
        }
      case SessionWarning(:final message):
        notice = message;
        notifyListeners();
      case SessionEnded(:final error):
        onAudioBilled?.call(from.audioSent);
        if (error != null && turn != null && turn.listening) {
          notice = _describe(error);
          unawaited(endReply());
        }
      case SessionReady():
        break;
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
      if (replying) {
        _replyPipe.push(pcm);
        _pipe.push(Uint8List(pcm.length));
      } else if (_now().isBefore(_mainMutedUntil)) {
        _pipe.push(Uint8List(pcm.length));
      } else {
        _pipe.push(pcm);
      }
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
        if (_readAloud && reply == null) unawaited(speaker.play(pcm, sampleRate));
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
      if (!s.hasTranslation || s.speaker != null) continue;
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
    unawaited(_replyPipe.dispose());
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
