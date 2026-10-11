import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/link_preview_service.dart';
import '../domain/link_detect.dart';
import '../domain/wall_models.dart';
import '../domain/wall_providers.dart';
import 'wall_visuals.dart';

Future<void> showAddToWallSheet(
  BuildContext context, {
  String? initialUrl,
  String? initialNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(LovRadius.xl)),
    ),
    builder: (_) => AddToWallSheet(initialUrl: initialUrl, initialNote: initialNote),
  );
}

class AddToWallSheet extends ConsumerStatefulWidget {
  const AddToWallSheet({super.key, this.initialUrl, this.initialNote});

  final String? initialUrl;
  final String? initialNote;

  @override
  ConsumerState<AddToWallSheet> createState() => _AddToWallSheetState();
}

class _AddToWallSheetState extends ConsumerState<AddToWallSheet> {
  late final TextEditingController _url =
      TextEditingController(text: widget.initialUrl ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.initialNote ?? '');

  WallCollection? _collection;
  bool _clipboardHasText = false;
  Timer? _debounce;

  int _previewToken = 0;
  String? _previewFor;
  Future<LinkPreview?>? _previewFuture;
  LinkPreview? _preview;
  bool _loadingPreview = false;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.addListener(_onUrlChanged);
    _note.addListener(() => setState(() {}));
    // setState isn't allowed during initState, so a pre-filled link (from the
    // Share menu) starts loading its preview right after the first frame.
    if (_validUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
    }
    _checkClipboard();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _url.dispose();
    _note.dispose();
    super.dispose();
  }

  String? get _validUrl => extractFirstUrl(_url.text);
  bool get _urlTextInvalid => _url.text.trim().isNotEmpty && _validUrl == null;
  bool get _canSubmit =>
      !_submitting &&
      !_urlTextInvalid &&
      (_validUrl != null || _note.text.trim().isNotEmpty);

  /// Only asks WHETHER there is text — never reads it until the user taps,
  /// so no "pasted from…" banner/toast.
  Future<void> _checkClipboard() async {
    if (_url.text.isNotEmpty) return;
    try {
      final has = await Clipboard.hasStrings();
      if (mounted) setState(() => _clipboardHasText = has);
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null) return;
    final parsed = parseSharedText(text);
    setState(() => _clipboardHasText = false);
    // Set the controllers outside setState: their listeners call setState.
    if (parsed.url != null) {
      _url.text = parsed.url!;
    } else if (_note.text.isEmpty && parsed.note != null) {
      _note.text = parsed.note!;
    }
  }

  void _onUrlChanged() {
    setState(() => _error = null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadPreview);
  }

  void _loadPreview() {
    if (!mounted) return;
    final url = _validUrl;
    if (url == null) {
      if (_previewFor != null) {
        setState(() {
          _previewFor = null;
          _previewFuture = null;
          _preview = null;
          _loadingPreview = false;
        });
      }
      return;
    }
    if (url == _previewFor) return;
    final token = ++_previewToken;
    final future = ref.read(linkPreviewServiceProvider).fetch(url);
    setState(() {
      _previewFor = url;
      _previewFuture = future;
      _preview = null;
      _loadingPreview = true;
    });
    future.then((p) {
      if (!mounted || token != _previewToken) return;
      setState(() {
        _preview = p;
        _loadingPreview = false;
      });
    });
  }

  Future<void> _submit() async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final selfId = ref.read(wallSelfIdProvider);
    if (couple == null || selfId == null) return;
    final url = _validUrl;
    final note = _note.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      LinkPreview? preview;
      if (url != null) {
        if (url != _previewFor) _loadPreview();
        preview = await (_previewFuture ?? Future<LinkPreview?>.value(null));
      }
      await ref.read(wallRepositoryProvider).addItem(
            coupleId: couple.id,
            userId: selfId,
            url: url,
            title: url == null ? null : (preview?.title ?? domainOf(url)),
            description: preview?.description,
            imageUrl: preview?.imageUrl,
            source: url == null ? WallSource.note : classifyUrl(url),
            collection: _collection,
            note: note.isEmpty ? null : note,
          );
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't share — check your connection and try again.";
      });
    }
  }

  InputDecoration _decoration(String hint, IconData icon, {String? error, Widget? suffix}) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(LovRadius.md),
          borderSide: BorderSide(color: c),
        );
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      errorText: error,
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(scheme.primary),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spouse = ref.watch(wallSpouseNameProvider);
    // Keep the couple stream subscribed while the sheet is open so the value
    // is already resolved when the user taps Share (_submit reads it).
    ref.watch(currentCoupleProvider);
    final url = _validUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(LovSpace.lg, 0, LovSpace.lg, LovSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add to our Wall', style: theme.textTheme.titleLarge),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: _decoration(
                'Paste a link',
                Icons.link_rounded,
                error: _urlTextInvalid ? "That doesn't look like a link" : null,
                suffix: url != null
                    ? Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20)
                    : null,
              ),
            ),
            if (_clipboardHasText && _url.text.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: LovSpace.sm),
                  child: ActionChip(
                    avatar: const Icon(Icons.content_paste_rounded, size: 16),
                    label: const Text('Paste copied link'),
                    onPressed: _pasteFromClipboard,
                  ),
                ),
              ),
            AnimatedSize(
              duration: LovDuration.standard,
              curve: LovCurves.standard,
              child: url == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: LovSpace.md),
                      child: _PreviewRow(url: url, preview: _preview, loading: _loadingPreview),
                    ),
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              inputFormatters: [LengthLimitingTextInputFormatter(1000)],
              decoration: _decoration('Add a note… (optional)', Icons.edit_note_rounded),
            ),
            const SizedBox(height: LovSpace.md),
            Text(
              'COLLECTION',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: LovSpace.sm),
            Wrap(
              spacing: LovSpace.sm,
              runSpacing: LovSpace.sm,
              children: [
                for (final c in WallCollection.values)
                  WallPill(
                    label: c.label,
                    selected: _collection == c,
                    onTap: () => setState(() => _collection = _collection == c ? null : c),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: LovSpace.md),
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
            ],
            const SizedBox(height: LovSpace.lg),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LovRadius.md)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_error != null ? 'Try again' : 'Share with ${spouse ?? 'your partner'}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.url, required this.preview, required this.loading});

  final String url;
  final LinkPreview? preview;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final domain = domainOf(url) ?? url;
    return Container(
      padding: const EdgeInsets.all(LovSpace.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LovRadius.md),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: loading
                ? const LovShimmerBox(width: 56, height: 56, radius: LovRadius.sm)
                : WallThumbnail(
                    source: classifyUrl(url),
                    imageUrl: preview?.imageUrl,
                    borderRadius: LovRadius.sm,
                    showSourcePill: false,
                  ),
          ),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: loading
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LovShimmerBox(width: 160, height: 12),
                      SizedBox(height: 6),
                      LovShimmerBox(width: 90, height: 10),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preview?.title ?? domain,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
