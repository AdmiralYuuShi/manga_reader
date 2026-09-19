import 'package:flutter/material.dart';

import 'core/api/api_client.dart';

void main() => runApp(const MangaTranslatorApp());

class MangaTranslatorApp extends StatelessWidget {
  const MangaTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Manga Translator',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ApiClient _apiClient = widget.apiClient ?? ApiClient();
  late Future<HealthResponse> _health = _apiClient.getHealth();

  void _refresh() => setState(() => _health = _apiClient.getHealth());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manga Translator')),
    body: Center(
      child: FutureBuilder<HealthResponse>(
        future: _health,
        builder: (context, snapshot) {
          final connected = snapshot.hasData && snapshot.data!.status == 'ok';
          final message = snapshot.connectionState != ConnectionState.done
              ? 'Checking backend...'
              : connected
              ? 'Backend connected'
              : 'Backend unavailable';
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                connected ? Icons.cloud_done : Icons.cloud_off,
                size: 48,
                color: connected ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 12),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          );
        },
      ),
    ),
  );
}
