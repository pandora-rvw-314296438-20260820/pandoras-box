import 'package:flutter/material.dart';
import '../../core/design/pandora_tokens.dart';

class PandoraBuildTheatre extends StatefulWidget {
  const PandoraBuildTheatre({super.key});

  @override
  State<PandoraBuildTheatre> createState() => _PandoraBuildTheatreState();
}

class _PandoraBuildTheatreState extends State<PandoraBuildTheatre> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RotationTransition(
            turns: _controller,
            child: Image.asset(
              'assets/brand/pandora-product-mark-ui-1024.png',
              width: 80,
              height: 80,
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),
          Text(
            'Understanding your business...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
