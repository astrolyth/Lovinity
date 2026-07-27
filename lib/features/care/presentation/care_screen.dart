// lib/features/care/presentation/care_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/care_tip.dart';
import '../domain/care_providers.dart';
import '../../cycle/domain/cycle_providers.dart';

class CareScreen extends ConsumerWidget {
  const CareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWife = ref.watch(isWifeProvider);
    final async = ref.watch(careTipsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(isWife ? 'Caring for you' : 'Caring for her')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10)),
              child: const Text('General guidance, not medical advice; '
                  'consult a doctor for health concerns.',
                  style: TextStyle(fontStyle: FontStyle.italic)),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (tips) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final t in tips) _TipCard(tip: t),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip});
  final CareTip tip;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tip.title, style: t.titleMedium),
        const SizedBox(height: 6),
        Text(tip.body),
        if (tip.islamicReference != null) ...[
          const SizedBox(height: 8),
          Text(tip.islamicReference!, style: t.bodySmall),
        ],
        if (tip.scientificReference != null) ...[
          const SizedBox(height: 4),
          Text(tip.scientificReference!, style: t.bodySmall),
        ],
        if (tip.isPendingReview && tip.islamicReference != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.info_outline, size: 14),
            const SizedBox(width: 4),
            Expanded(child: Text('Please verify this reference with a qualified scholar.',
                style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic))),
          ]),
        ],
      ]),
    ));
  }
}
