import 'package:flutter/widgets.dart';

import '../calendar/calendar_source.dart';
import '../demo/demo_http.dart';
import '../demo/demo_library.dart';
import '../demo/demo_translate.dart' as demo;
import '../live/audio_ports.dart';
import '../live/session_pipe.dart';
import '../openai/realtime_translate.dart';
import '../openai/responses_client.dart';
import '../openai/text_ai.dart';
import '../openai/transcribe_client.dart';
import '../storage/key_store.dart';
import '../storage/library_store.dart';
import '../storage/settings_store.dart';

/// Everything the screens need, built once in `main`.
///
/// With "Chế độ thử" on ([SettingsStore.demoMode]) the AI comes from sample
/// backends (`lib/demo/`) instead of OpenAI: no key, no cost. Microphone and
/// speakers stay real, and the app's own client code still runs.
class AppServices {
  AppServices({
    required this.keys,
    required this.settings,
    required this.library,
    required this.newMic,
    required this.speaker,
    this.awake = const NoScreenAwake(),
    this.background = const NoBackgroundRecording(),
    SessionOpener? opener,
    ResponsesClient? responses,
    TranscribeClient? transcriber,
    SessionOpener? demoOpener,
    TextAi? demoTextAi,
    TranscribeClient? demoTranscriber,
    CalendarSource? calendar,
    CalendarSource? demoCalendar,
  })  : // ignore: prefer_initializing_formals
        _calendar = calendar,
        _demoCalendar = demoCalendar ?? DemoCalendarSource() {
    final key = keyProviderFor(keys);
    _opener = opener ?? (cfg) async => TranslateSession.open(apiKey: await key(), config: cfg);
    _textAi = TextAi(
      responses ?? ResponsesClient(key: key),
      translationModel: settings.translationModel,
      onUsage: settings.addTokens,
    );
    _transcriber = transcriber ?? TranscribeClient(key: key);
    final demoHttp = demoHttpClient();
    _demoOpener = demoOpener ?? demo.demoOpener();
    _demoTextAi = demoTextAi ?? TextAi(ResponsesClient(key: () async => 'demo', httpClient: demoHttp));
    _demoTranscriber = demoTranscriber ?? TranscribeClient(key: () async => 'demo', httpClient: demoHttp);
  }

  final KeyStore keys;
  final SettingsStore settings;
  final LibraryStore library;
  final MicSource Function() newMic;
  final PcmSink speaker;
  final ScreenAwake awake;

  /// Keeps a meeting recording with the screen off.
  final BackgroundRecording background;

  late final SessionOpener _opener;
  late final TextAi _textAi;
  late final TranscribeClient _transcriber;
  late final SessionOpener _demoOpener;
  late final TextAi _demoTextAi;
  late final TranscribeClient _demoTranscriber;

  bool get demoMode => settings.demoMode;

  SessionOpener get opener => demoMode ? _demoOpener : _opener;
  TextAi get textAi => demoMode ? _demoTextAi : _textAi;
  TranscribeClient get transcriber => demoMode ? _demoTranscriber : _transcriber;

  final CalendarSource? _calendar;
  final CalendarSource _demoCalendar;

  /// "Sắp tới": the phone's calendar, or sample meetings in demo mode.
  /// Null when the platform has none (tests).
  CalendarSource? get calendar => demoMode ? _demoCalendar : _calendar;

  /// Records billed live-translation audio; nothing is billed in demo mode.
  void Function(Duration)? get onAudioBilled => demoMode ? null : settings.addTranslateAudio;

  /// Bumped whenever the Library changes, so lists refresh.
  final libraryVersion = ValueNotifier<int>(0);

  void libraryChanged() => libraryVersion.value++;

  /// Whether the app can run: a saved key, or demo mode.
  Future<bool> hasKey() async => demoMode || ((await keys.read()) ?? '').trim().isNotEmpty;

  /// Turns "Chế độ thử" on (adding the sample Library items) or off
  /// (removing them).
  Future<void> setDemoMode(bool on) async {
    settings.demoMode = on;
    await settings.save();
    if (on) {
      await seedDemoLibrary(library);
    } else {
      await clearDemoLibrary(library);
    }
    libraryChanged();
  }
}

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => services != oldWidget.services;
}
