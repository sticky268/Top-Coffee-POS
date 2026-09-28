import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          const Icon(
            Icons.local_cafe,
            size: 72,
          ),
          const SizedBox(height: 16),
          Text(
            'TOP COFFEE POS',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coffee Shop Sales Management System',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Version'),
                  trailing: Text('0.1.0+1'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.coffee_outlined),
                  title: Text('Application'),
                  trailing: Text('Top Coffee POS'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
