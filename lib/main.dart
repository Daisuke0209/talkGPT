// Dart imports:
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';
import 'package:openai_client/openai_client.dart';
import 'package:openai_client/src/model/openai_chat/chat_message.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

// Project imports:
import 'credential.dart';

enum TtsState { playing, stopped, paused, continued }

void main() => runApp(const talkGPTApp());

class talkGPTApp extends StatefulWidget {
  const talkGPTApp({super.key});

  @override
  _talkGPTAppState createState() => _talkGPTAppState();
}

class _talkGPTAppState extends State<talkGPTApp> {
  bool _hasSpeech = false;
  double level = 0.0;
  double minSoundLevel = 50000;
  double maxSoundLevel = -50000;
  String lastWords = '';
  String lastError = '';
  String chatGPTResponse = '';
  String lastStatus = '';
  final String _localeId = 'en-US';
  final SpeechToText speech = SpeechToText();

  @override
  void initState() {
    super.initState();
    initSpeechState();
  }

  Future<void> initSpeechState() async {
    print("initSpeechState");
    try {
      var hasSpeech = await speech.initialize(
        onError: errorListener,
        onStatus: statusListener,
      );

      if (!mounted) return;

      setState(() {
        _hasSpeech = hasSpeech;
      });
    } catch (e) {
      setState(() {
        lastError = 'Speech recognition failed: ${e.toString()}';
        _hasSpeech = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('talkGPT'),
        ),
        body: Column(children: [
          Container(
            child: Column(
              children: <Widget>[
                SpeechControlWidget(_hasSpeech, speech.isListening,
                    startListening, stopListening),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: RecognitionResultsWidget(lastWords: lastWords, level: level),
          ),
          Expanded(flex: 4, child: chatGPTResponseWidget(lastWords: lastWords))
        ]),
      ),
    );
  }

  void startListening() {
    lastWords = '';
    lastError = '';
    speech.listen(
      onResult: resultListener,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: _localeId,
      onSoundLevelChange: soundLevelListener,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
    setState(() {});
  }

  void stopListening() {
    speech.stop();
    setState(() {
      level = 0.0;
    });
  }

  /// This callback is invoked each time new recognition results are
  /// available after `listen` is called.
  void resultListener(SpeechRecognitionResult result) {
    setState(() {
      lastWords = result.recognizedWords;
    });
  }

  void soundLevelListener(double level) {
    minSoundLevel = min(minSoundLevel, level);
    maxSoundLevel = max(maxSoundLevel, level);
    setState(() {
      this.level = level;
    });
  }

  void errorListener(SpeechRecognitionError error) {
    setState(() {
      lastError = '${error.errorMsg} - ${error.permanent}';
    });
  }

  void statusListener(String status) {
    setState(() {
      lastStatus = status;
    });
  }
}

/// Displays the most recently recognized words and the sound level.
class RecognitionResultsWidget extends StatelessWidget {
  const RecognitionResultsWidget({
    Key? key,
    required this.lastWords,
    required this.level,
  }) : super(key: key);

  final String lastWords;
  final double level;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              Container(
                color: Theme.of(context).selectedRowColor,
                child: Center(
                  child: Text(
                    lastWords,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }
}

/// Controls to start and stop speech recognition
class SpeechControlWidget extends StatelessWidget {
  const SpeechControlWidget(
      this.hasSpeech, this.isListening, this.startListening, this.stopListening,
      {Key? key})
      : super(key: key);

  final bool hasSpeech;
  final bool isListening;
  final void Function() startListening;
  final void Function() stopListening;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        TextButton(
          onPressed: !hasSpeech || isListening ? null : startListening,
          child: const Text('Start'),
        ),
        TextButton(
          onPressed: isListening ? stopListening : null,
          child: const Text('Stop'),
        )
      ],
    );
  }
}

class chatGPTResponseWidget extends StatefulWidget {
  const chatGPTResponseWidget({Key? key, required this.lastWords})
      : super(key: key);
  final String lastWords;

  @override
  State<chatGPTResponseWidget> createState() => chatGPTResponseState();
}

class chatGPTResponseState extends State<chatGPTResponseWidget> {
  late Future<String> future;
  // For TTS
  late FlutterTts flutterTts;
  TtsState ttsState = TtsState.stopped;
  double volume = 1.0;
  double pitch = 1.0;
  double rate = 0.5;
  late Future<String> _newVoiceText;

  bool get isIOS => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    initTts();
    future = chatGPT('Please introduce yourself.');
  }

  void askchatGPT() {
    setState(() {
      future =
          chatGPT('${widget.lastWords}.Please respond in 50 words or less.');
      _newVoiceText = future;

      future.then((value) => flutterTts.speak(value));
    });
  }

  Future<String> chatGPT(String text) async {
    print('chatGPT is called.');
    const configuration = OpenAIConfiguration(apiKey: API_KEY);
    final client = OpenAIClient(
      configuration: configuration,
      enableLogging: true,
    );

    final chat = await client.chat.create(
      model: 'gpt-3.5-turbo',
      messages: [
        ChatMessage(
          role: 'user',
          content: text,
        )
      ],
    ).data;
    return chat.choices.first.message.content;
  }

  initTts() {
    flutterTts = FlutterTts();
    flutterTts.setLanguage('en-US');
    flutterTts.setVolume(volume);
    flutterTts.setSpeechRate(rate);
    flutterTts.setPitch(pitch);

    _setAwaitOptions();
  }

  Future _setAwaitOptions() async {
    await flutterTts.awaitSpeakCompletion(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ElevatedButton(
        onPressed: () {
          askchatGPT();
        },
        child: const Text('Send ChatGPT'),
      ),
      FutureBuilder<String>(
        future: future,
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.none:
              return const Text("none");
            case ConnectionState.waiting:
              return const Text("waiting");
            case ConnectionState.active:
              return const Text("active");
            case ConnectionState.done:
              return Text(snapshot.data!);
          }
        },
      ),
    ]);
  }
}
