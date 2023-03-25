import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:openai_client/openai_client.dart';
import 'package:openai_client/src/model/openai_chat/chat_message.dart';

import 'package:http/http.dart' as http;

import 'credential.dart';


void main() => runApp(SpeechSampleApp());

class SpeechSampleApp extends StatefulWidget {
  @override
  _SpeechSampleAppState createState() => _SpeechSampleAppState();
}

class _SpeechSampleAppState extends State<SpeechSampleApp> {
  bool _hasSpeech = false;
  double level = 0.0;
  double minSoundLevel = 50000;
  double maxSoundLevel = -50000;
  String lastWords = '';
  String lastError = '';
  String chatGPTResponse = '';
  String lastStatus = '';
  String _localeId = 'en-US';
  final SpeechToText speech = SpeechToText();

  @override
  void initState() {
    super.initState();
    this.initSpeechState();
  }
  

  /// This initializes SpeechToText. That only has to be done
  /// once per application, though calling it again is harmless
  /// it also does nothing. The UX of the sample app ensures that
  /// it can only be called once.
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
          title: const Text('Speech to Text Example'),
        ),
        body: Column(children: [
          Container(
            child: Column(
              children: <Widget>[
                SpeechControlWidget(_hasSpeech, speech.isListening,
                    startListening, stopListening, cancelListening),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: RecognitionResultsWidget(
              lastWords: lastWords, level: level),
          ),
          Expanded(
            flex: 4,
            child: chatGPTResponseWidget(lastWords: lastWords)
          )
        ]),
      ),
    );
  }

  // This is called each time the users wants to start a new speech
  // recognition session
  void startListening() {
    lastWords = '';
    lastError = '';
    speech.listen(
      onResult: resultListener,
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 3),
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

  void cancelListening() {
    speech.cancel();
    setState(() {
      level = 0.0;
    });
  }

  /// This callback is invoked each time new recognition results are
  /// available after `listen` is called.
  void resultListener(SpeechRecognitionResult result) {
    setState(() {
      lastWords = '${result.recognizedWords}';
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
      lastStatus = '$status';
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
  const SpeechControlWidget(this.hasSpeech, this.isListening,
      this.startListening, this.stopListening, this.cancelListening,
      {Key? key})
      : super(key: key);

  final bool hasSpeech;
  final bool isListening;
  final void Function() startListening;
  final void Function() stopListening;
  final void Function() cancelListening;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        TextButton(
          onPressed: !hasSpeech || isListening ? null : startListening,
          child: Text('Start'),
        ),
        TextButton(
          onPressed: isListening ? stopListening : null,
          child: Text('Stop'),
        ),
        TextButton(
          onPressed: isListening ? cancelListening : null,
          child: Text('Cancel'),
        )
      ],
    );
  }
}


class chatGPTResponseWidget extends StatefulWidget {
  const chatGPTResponseWidget({Key? key, required this.lastWords}) : super(key: key);
  final String lastWords;

  @override
  State<chatGPTResponseWidget> createState() => chatGPTResponseState();
}

class chatGPTResponseState extends State<chatGPTResponseWidget> {
  late Future<String> future;
  @override
  void initState() {
    super.initState();
    future = chatGPT('Please introduce yourself.');
  }

  void updateParameter() {
    setState(() {
      future = chatGPT(widget.lastWords + '.Please respond in 50 words or less.');
    });
  }

  Future<String> chatGPT(String text) async {
    print('chatGPT is called.');
    final configuration = OpenAIConfiguration(apiKey: API_KEY as String);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
            updateParameter();
          },
          child: Text('Send ChatGPT'),
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
        )
      ]
    );
  }
}


