import 'dart:typed_data';

import '../openai/realtime_translate.dart';

/// A reply ("Tôi trả lời") while it is being spoken or finished.
class LiveTurn {
  LiveTurn(this.speaker, this.at, this.session);
  final int speaker;
  final Duration at;
  TranslateSession? session;
  String source = '';
  String translation = '';
  bool listening = true;
  final List<(Uint8List, int)> heldAudio = [];
}
