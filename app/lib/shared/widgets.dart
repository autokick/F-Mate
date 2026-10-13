import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';

/// 둥근 카드 (테두리형)
class FmCard extends StatelessWidget {
  const FmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FmSpace.l),
    this.onTap,
    this.color = Colors.white,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(FmRadius.card);
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: FmColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 데이터가 없을 때. 샘플 데이터를 보여주지 않고 이 화면을 쓴다.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: icon,
      iconColor: FmColors.brandDark,
      iconBackground: FmColors.brandSoft,
      title: title,
      message: message,
      action: actionLabel == null
          ? null
          : OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
    );
  }
}

/// 네트워크 오류 등 실패 상태
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _StateLayout(
      icon: icon,
      iconColor: FmColors.danger,
      iconBackground: FmColors.dangerSoft,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
    );
  }
}

/// 로딩 상태
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label = '불러오는 중'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(FmSpace.xxl),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FmSpace.xl, vertical: FmSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: iconColor),
          ),
          const SizedBox(height: FmSpace.l),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: FmColors.textPrimary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: FmSpace.s),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5, color: FmColors.textSecondary),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: FmSpace.l),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 섹션 제목
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.xl, FmSpace.l, FmSpace.s),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: FmColors.textPrimary,
                ),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 서버 연결 전 기능임을 알리는 띠. 기능이 동작하는 척하지 않기 위해 사용한다.
class NotConnectedBanner extends StatelessWidget {
  const NotConnectedBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(FmSpace.l, FmSpace.s, FmSpace.l, 0),
      padding: const EdgeInsets.all(FmSpace.m),
      decoration: BoxDecoration(
        color: FmColors.surfaceMuted,
        borderRadius: BorderRadius.circular(FmRadius.control),
        border: Border.all(color: FmColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: FmColors.textSecondary),
          const SizedBox(width: FmSpace.s),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, height: 1.4, color: FmColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

void showFmSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// 프로필 사진 (없으면 이니셜)
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.url, required this.name, this.size = 40});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first;
    return Semantics(
      label: '$name 프로필 사진',
      image: true,
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: url == null
              ? Container(
                  color: FmColors.brandSoft,
                  alignment: Alignment.center,
                  child: Text(initial,
                      style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: FmColors.brandDark)),
                )
              : Image.network(url!, fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(color: FmColors.surfaceMuted)),
        ),
      ),
    );
  }
}

/// 처리 중 표시가 되는 버튼 (중복 탭 방지)
class LoadingButton extends StatefulWidget {
  const LoadingButton({super.key, required this.label, required this.onPressed, this.outlined = false, this.expand = true});

  final String label;
  final Future<void> Function()? onPressed;
  final bool outlined;
  final bool expand;

  @override
  State<LoadingButton> createState() => _LoadingButtonState();
}

class _LoadingButtonState extends State<LoadingButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
        : Text(widget.label);
    final onPressed = widget.onPressed == null || _busy ? null : _tap;
    final button = widget.outlined
        ? OutlinedButton(onPressed: onPressed, child: child)
        : FilledButton(onPressed: onPressed, child: child);
    return widget.expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// 오류를 스낵바로 (서버 오류 코드의 한국어 문구 사용)
void showError(BuildContext context, Object e) {
  showFmSnack(context, ApiError.from(e).message);
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, String? message, String confirm = '확인', bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirm, style: TextStyle(color: destructive ? FmColors.danger : null, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 한 줄 입력 대화상자 (사유 입력 등)
Future<String?> promptDialog(BuildContext context, {required String title, String? hint, int maxLength = 200}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('확인')),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// 테스트 결제 표시 (실결제처럼 보이지 않게)
class TestModeBadge extends StatelessWidget {
  const TestModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FmSpace.s, vertical: FmSpace.xs),
      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(FmRadius.chip)),
      child: const Text('테스트 결제 · 실제 청구 없음',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
    );
  }
}

/// 상태 라벨 칩
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.color = FmColors.brandDark, this.background = FmColors.brandSoft});

  final String label;
  final Color color;
  final Color background;

  factory StatusChip.reservation(String label, String status) {
    switch (status) {
      case 'CONFIRMED':
      case 'COMPLETED':
        return StatusChip(label: label);
      case 'PENDING_PAYMENT':
        return StatusChip(label: label, color: const Color(0xFF92400E), background: const Color(0xFFFEF3C7));
      default:
        return StatusChip(label: label, color: FmColors.textSecondary, background: FmColors.surfaceMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(FmRadius.chip)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// 라벨 - 값 한 줄
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 14, color: FmColors.textSecondary))),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 14, color: FmColors.textPrimary, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }
}
