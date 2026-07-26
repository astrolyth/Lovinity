import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';

import '../theme/tokens.dart';

class HijriDate extends StatelessWidget {
  const HijriDate({
    super.key,
    this.date,
    this.style,
    this.showBoth = true,
    this.hijriFirst = true,
  });

  final DateTime? date;
  final TextStyle? style;
  final bool showBoth;
  final bool hijriFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greg = date ?? DateTime.now();
    final hijri = HijriCalendar.fromDate(greg);
    final gregLabel = DateFormat('EEEE, d MMMM').format(greg);
    final hijriLabel =
        '${hijri.hDay} ${hijri.longMonthName} ${hijri.hYear} AH';

    final effectiveStyle =
        style ?? theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
        );

    if (!showBoth) {
      return Text(hijriFirst ? hijriLabel : gregLabel, style: effectiveStyle);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hijriFirst ? hijriLabel : gregLabel,
          style: effectiveStyle,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LovSpace.sm),
          child: Text('/', style: effectiveStyle),
        ),
        Text(
          hijriFirst ? gregLabel : hijriLabel,
          style: effectiveStyle,
        ),
      ],
    );
  }
}
