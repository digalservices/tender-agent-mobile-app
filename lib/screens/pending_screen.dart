import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Shown while an administrator has not yet approved the account (status PENDING).
/// `onRefresh` re-reads the account; it returns true when the account is now approved.
class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key, required this.auth, required this.onRefresh});
  final AuthService auth;
  final Future<bool> Function() onRefresh;

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  bool _checking = false;
  String? _message;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    String? message;
    try {
      final approved = await widget.onRefresh();
      if (!approved) {
        message = 'Still waiting for approval. Please check again later.';
      }
    } catch (e) {
      message = 'Could not check: $e';
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _message = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Waiting for approval',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your account is created. Our team will activate it shortly - then you can start using Tender Mitra.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _checking ? null : _check,
                  child: _checking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Check again'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, textAlign: TextAlign.center),
                ],
                TextButton(
                  onPressed: widget.auth.signOut,
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
