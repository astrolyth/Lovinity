import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../settings/domain/settings_providers.dart';
import '../domain/cycle_providers.dart';

class CycleScreen extends ConsumerWidget {
  const CycleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeCycleProvider);
    final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
    final prediction = ref.watch(cyclePredictionProvider);
    final df = DateFormat.MMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Cycle')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (active != null)
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resting 🤍', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Prayers are excused and your score is paused. '
                  'This is a mercy — take care of yourself.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await ref.read(cycleRepositoryProvider)
                      .endCycle(recordId: active.id, endedOn: DateTime.now());
                },
                child: const Text('End period'),
              ),
            ]),
          ))
        else
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Track your cycle', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Starting your period pauses prayer scoring and marks '
                  'prayers as excused until you end it.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final session = ref.read(authSessionProvider).asData?.value;
                  final couple = ref.read(currentCoupleProvider).asData?.value;
                  if (session == null || couple == null) return;
                  final shareDefault = ref.read(shareCycleByDefaultProvider);
                  await ref.read(cycleRepositoryProvider).startCycle(
                        userId: session.user.id,
                        coupleId: couple.id,
                        startedOn: DateTime.now(),
                        visibility: shareDefault ? 'shared' : 'private',
                      );
                },
                child: const Text('Start period'),
              ),
            ]),
          )),
        const SizedBox(height: 16),
        if (prediction.nextStart != null)
          Card(child: ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text('Next period around ${df.format(prediction.nextStart!)}'),
            subtitle: Text('Avg cycle ${prediction.avgCycleLength} days · '
                'period ${prediction.avgPeriodLength} days'),
          )),
        const SizedBox(height: 16),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        for (final r in history)
          ListTile(
            dense: true,
            leading: const Icon(Icons.circle, size: 10),
            title: Text(r.endedOn == null
                ? '${df.format(r.startedOn)} — ongoing'
                : '${df.format(r.startedOn)} – ${df.format(r.endedOn!)}'),
          ),
      ]),
    );
  }
}
