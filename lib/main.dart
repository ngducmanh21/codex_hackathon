import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/services.dart';
import 'calendar/calendar_source.dart';
import 'platform/device_audio.dart';
import 'storage/key_store.dart';
import 'storage/library_store.dart';
import 'storage/settings_store.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final settings = SettingsStore(File('${docs.path}/settings.json'));
  await settings.load();
  final services = AppServices(
    keys: SecureKeyStore(),
    settings: settings,
    library: LibraryStore(Directory('${docs.path}/library')),
    newMic: RecordMic.new,
    speaker: PcmSpeaker(),
    awake: const WakelockAwake(),
    calendar: DeviceCalendarSource(),
  );
  runApp(ScoaiVoiceApp(services: services));
}

class ScoaiVoiceApp extends StatelessWidget {
  const ScoaiVoiceApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => Services(
        services: services,
        child: MaterialApp(
          title: 'SCOAI Voice',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const HomeScreen(),
        ),
      );
}
