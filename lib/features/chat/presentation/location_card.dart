import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/live_location.dart';

/// A live-location bubble: where they are, until when, and a Maps link.
/// The sender also gets "Stop sharing" while their share is live.
class LocationCard extends ConsumerWidget {
  const LocationCard({
    super.key,
    required this.messageId,
    required this.json,
    required this.isOwn,
    required this.color,
  });
  final String messageId;
  final String json;
  final bool isOwn;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final lat = (m['lat'] as num).toDouble(), lon = (m['lon'] as num).toDouble();
    final until = DateTime.fromMillisecondsSinceEpoch((m['until'] as num).toInt());
    final live = m['ended'] != true && until.isAfter(DateTime.now());
    final mine = isOwn && ref.watch(liveLocationProvider) == messageId;
    final status = live
        ? 'Live until ${DateFormat.jm().format(until)}'
        : 'Sharing ended';

    return SizedBox(
      width: 230,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                live ? Icons.my_location_rounded : Icons.location_on_outlined,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live location',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: color.withValues(alpha: .75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    Platform.isIOS
                        ? 'https://maps.apple.com/?ll=$lat,$lon&q=$lat,$lon'
                        : 'geo:$lat,$lon?q=$lat,$lon',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open in Maps'),
              ),
              if (mine && live)
                TextButton(
                  onPressed: () => ref.read(liveLocationProvider.notifier).stop(),
                  child: const Text('Stop sharing'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
