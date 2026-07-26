import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion.dart';
import '../theme/tokens.dart';

/// A row of fixed slots the user types into, one glyph per slot.
///
/// Emits [onCompleted] once every slot has a character.
/// Emits [onChanged] on every edit.
/// Call [ShakeController.shake] on the returned controller to shake.
///
/// Accepts either digits (numeric keyboard) or uppercase letters+digits
/// (text keyboard with auto-uppercase).
class SakDigitSlots extends StatefulWidget {
  const SakDigitSlots({
    super.key,
    required this.length,
    required this.onCompleted,
    this.onChanged,
    this.mode = SakDigitMode.numeric,
    this.controller,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final SakDigitMode mode;
  final SakDigitSlotsController? controller;
  final bool autofocus;

  @override
  State<SakDigitSlots> createState() => _SakDigitSlotsState();
}

enum SakDigitMode { numeric, alphanumericUppercase }

class SakDigitSlotsController {
  _SakDigitSlotsState? _state;
  void _attach(_SakDigitSlotsState s) => _state = s;
  void _detach() => _state = null;

  /// Trigger a shake animation. Also clears the input.
  void shake() => _state?._shake();

  /// Clear all slots.
  void clear() => _state?._clear();
}

class _SakDigitSlotsState extends State<SakDigitSlots>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant SakDigitSlots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() {});
  }

  void _shake() {
    _shakeController.forward(from: 0);
    _clear();
    _focusNode.requestFocus();
  }

  void _handleChanged(String v) {
    final normalized = _normalize(v);
    if (normalized != v) {
      _controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    widget.onChanged?.call(normalized);
    if (normalized.length == widget.length) {
      widget.onCompleted(normalized);
    }
    setState(() {});
  }

  String _normalize(String v) {
    var out = v;
    if (widget.mode == SakDigitMode.alphanumericUppercase) {
      out = out.toUpperCase();
    }
    if (out.length > widget.length) out = out.substring(0, widget.length);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chars = _controller.text.characters.toList();
    // Pad up to length with empty slots
    while (chars.length < widget.length) {
      chars.add('');
    }

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        // 3 damping oscillations for the shake
        final t = _shakeController.value;
        final dx = t == 0
            ? 0.0
            : 8.0 * (1 - t) * math.sin(t * math.pi * 6);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Invisible input that drives the display slots
          Opacity(
            opacity: 0,
            child: SizedBox(
              width: 1,
              height: 1,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                keyboardType: widget.mode == SakDigitMode.numeric
                    ? TextInputType.number
                    : TextInputType.visiblePassword,
                enableSuggestions: false,
                autocorrect: false,
                textCapitalization:
                    widget.mode == SakDigitMode.alphanumericUppercase
                        ? TextCapitalization.characters
                        : TextCapitalization.none,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(widget.length),
                  if (widget.mode == SakDigitMode.numeric)
                    FilteringTextInputFormatter.digitsOnly,
                  if (widget.mode == SakDigitMode.alphanumericUppercase)
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9]'),
                    ),
                ],
                onChanged: _handleChanged,
              ),
            ),
          ),
          // Visible slots
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _focusNode.requestFocus(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  if (i > 0) const SizedBox(width: SakSpace.sm),
                  _Slot(
                    key: ValueKey('slot_$i'),
                    char: chars[i],
                    isActive: i == _controller.text.length,
                    theme: theme,
                    delay: Duration(milliseconds: 40 * i),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.char,
    required this.isActive,
    required this.theme,
    required this.delay,
  });

  final String char;
  final bool isActive;
  final ThemeData theme;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final filled = char.isNotEmpty;
    return SakEnter(
      delay: delay,
      duration: SakMotion.standard,
      child: AnimatedContainer(
        duration: SakMotion.standard,
        curve: SakMotion.enter,
        width: 48,
        height: 60,
        decoration: BoxDecoration(
          color: filled
              ? theme.colorScheme.secondary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(SakRadius.md),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: SakMotion.standard,
          switchInCurve: SakMotion.springOut,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Text(
            char,
            key: ValueKey(char.isEmpty ? '_$hashCode' : char),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: filled
                  ? theme.colorScheme.onSecondary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.35),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
