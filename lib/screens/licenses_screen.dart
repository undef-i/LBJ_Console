import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  Future<Map<String, String>> _load() async {
    final result = <String, String>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = entry.paragraphs.map((p) => p.text).join('\n\n');
      for (final package in entry.packages) {
        result.update(
          package,
          (existing) => '$existing\n\n$text',
          ifAbsent: () => text,
        );
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开放源代码许可')),
      body: FutureBuilder<Map<String, String>>(
        future: _load(),
        builder: (context, snapshot) {
          final licenses = snapshot.data ?? const <String, String>{};
          final names = licenses.keys.toList()..sort();
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LBJ Console',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '本程序是 GNU 通用公共许可证第 3 版下的自由软件。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Divider(),
              for (final name in names)
                ListTile(
                  title: Text(name),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => _LicenseDetailScreen(
                          package: name,
                          text: licenses[name]!,
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LicenseDetailScreen extends StatelessWidget {
  final String package;
  final String text;

  const _LicenseDetailScreen({required this.package, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(package)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: SelectableText(
          text,
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      ),
    );
  }
}
