import 'package:flutter/widgets.dart';

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
class AppServices {
  AppServices({
    required this.keys,
    required this.settings,
    required this.library,
    required this.newMic,
    required this.speaker,
    PcmSink? roomSpeaker,
    this.awake = const NoScreenAwake(),
    SessionOpener? opener,
    ResponsesClient? responses,
    TranscribeClient? transcriber,
  }) : roomSpeaker = roomSpeaker ?? speaker {
    final key = keyProviderFor(keys);
    this.opener = opener ??
        (cfg) async => TranslateSession.open(apiKey: await key(), config: cfg);
    textAi = TextAi(
      responses ?? ResponsesClient(key: key),
      translationModel: settings.translationModel,
      onUsage: settings.addTokens,
    );
    this.transcriber = transcriber ?? TranscribeClient(key: key);
  }

  final KeyStore keys;
  final SettingsStore settings;
  final LibraryStore library;
  final MicSource Function() newMic;
  final PcmSink speaker;

  /// The phone's loudspeaker, for "Phát biểu".
  final PcmSink roomSpeaker;
  final ScreenAwake awake;
  late final SessionOpener opener;
  late final TextAi textAi;
  late final TranscribeClient transcriber;

  /// Bumped whenever the Library changes, so lists refresh.
  final libraryVersion = ValueNotifier<int>(0);

  void libraryChanged() => libraryVersion.value++;

  Future<bool> hasKey() async => ((await keys.read()) ?? '').trim().isNotEmpty;
}

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => services != oldWidget.services;
}
