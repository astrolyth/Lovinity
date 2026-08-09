import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/planning_providers.dart';

/// Home card for the week: meals planned and what's still to buy.
class PlanningCard extends ConsumerWidget {
  const PlanningCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(viewedMealPlanProvider);
    final items = ref.watch(activeGroceryItemsProvider);
    final outstanding = items.where((i) => !i.checked).length;
    final planned = plan?.plannedCount ?? 0;

    return LovCard(
      onTap: () => context.push('/home/plan'),
      padding: const EdgeInsets.all(LovSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'THIS WEEK',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
          const SizedBox(height: LovSpace.md),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.restaurant_outlined,
                  label: planned == 0
                      ? 'No meals planned'
                      : '$planned meal${planned == 1 ? '' : 's'} planned',
                ),
              ),
              const SizedBox(width: LovSpace.md),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/home/groceries'),
                  child: _Stat(
                    icon: Icons.shopping_basket_outlined,
                    label: outstanding == 0
                        ? (items.isEmpty ? 'List empty' : 'All bought')
                        : '$outstanding to buy',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.secondary),
        const SizedBox(width: LovSpace.sm),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
