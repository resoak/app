import 'dart:async';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;
// 確保路徑正確
import 'stt_service.dart'; 

class RecordingService {
  final SttService sttService;
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription? _audioStreamSub;
  String? _lastPath;

  RecordingService({required this.sttService});

  Future<void> start() async {
    if (!await _audioRecorder.hasPermission()) return;

    final dir = await getApplicationDocumentsDirectory();
    _lastPath = p.join(dir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');

    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100), 
      path: _lastPath!
    );

    final stream = await _audioRecorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1)
    );

    List<int> buffer = [];
    _audioStreamSub = stream.listen((data) {
      buffer.addAll(data);
      if (buffer.length >= 12800) {
        final int16Data = Int16List.view(Uint8List.fromList(buffer).buffer);
        final samples = int16Data.map((e) => e / 32768.0).toList();
        sttService.acceptWaveform(samples, 16000);
        buffer.clear();
      }
    });
  }

  Future<String?> stop() async {
    await _audioStreamSub?.cancel();
    await _audioRecorder.stop();
    return _lastPath;
  }
}