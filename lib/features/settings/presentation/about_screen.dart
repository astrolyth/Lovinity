import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LovScaffold(
      title: 'About',
      child: ListView(
        children: [
          const SizedBox(height: LovSpace.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(LovRadius.lg),
            child: Image.asset('assets/branding/logo_full.jpg'),
          ),
          const SizedBox(height: LovSpace.xl),
          Text(
            'Lovinity',
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: LovSpace.xs),
          Text(
            'A private space, for the two of you.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: LovSpace.xxl),
        ],
      ),
    );
  }
}
