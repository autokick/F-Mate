import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'reservation_result_screen.dart';

/// 토스페이먼츠 결제창(WebView).
/// 결제 승인은 서버가 /pay/success 리다이렉트에서 직접 처리한다. 앱은 결과 페이지가 열리면 서버에 최종 상태를 묻는다.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.order, required this.reservationId});

  final PaymentOrder order;
  final String reservationId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final WebViewController _web;
  bool _loading = true;
  bool _finishing = false;
  Timer? _ticker;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    final services = AppScope.read(context);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('about:')) {
            return NavigationDecision.navigate;
          }
          _openExternalApp(url);
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _loading = false);
          if (url.startsWith(widget.order.successUrlPrefix) || url.startsWith(widget.order.failUrlPrefix)) {
            _finish();
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.order.checkoutUrl),
          headers: {'Authorization': 'Bearer ${services.api.tokens.access ?? ''}'});
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final exp = widget.order.holdExpiresAt;
    if (exp == null || !mounted) return;
    final r = exp.difference(DateTime.now());
    setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 카드사 앱·간편결제 앱 호출 (Android intent:// 포함)
  Future<void> _openExternalApp(String url) async {
    try {
      if (url.startsWith('intent:')) {
        final hash = url.indexOf('#Intent;');
        final params = <String, String>{};
        if (hash >= 0) {
          for (final part in url.substring(hash + 8).split(';')) {
            final kv = part.split('=');
            if (kv.length == 2) params[kv[0]] = kv[1];
          }
        }
        final body = url.substring(url.startsWith('intent://') ? 9 : 7, hash >= 0 ? hash : url.length);
        final scheme = params['scheme'];
        var launched = false;
        if (scheme != null) {
          launched = await launchUrl(Uri.parse('$scheme://$body'), mode: LaunchMode.externalApplication);
        }
        if (!launched) {
          final fallback = params['S.browser_fallback_url'];
          final pkg = params['package'];
          if (fallback != null) {
            await launchUrl(Uri.parse(Uri.decodeComponent(fallback)), mode: LaunchMode.externalApplication);
          } else if (pkg != null) {
            await launchUrl(Uri.parse('market://details?id=$pkg'), mode: LaunchMode.externalApplication);
          }
        }
        return;
      }
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showFmSnack(context, '결제 앱을 열 수 없어요. 앱이 설치되어 있는지 확인해 주세요');
    } catch (_) {
      if (mounted) showFmSnack(context, '결제 앱을 열 수 없어요. 앱이 설치되어 있는지 확인해 주세요');
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final s = AppScope.read(context);
    PaymentStatus? status;
    for (var i = 0; i < 8; i++) {
      try {
        status = await s.reservations.paymentStatus(widget.order.orderId);
        if (!status.isPending) break;
        if (i == 3) await s.reservations.reconcile(widget.order.orderId);
      } catch (_) {
        // 잠시 후 다시 확인
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ReservationResultScreen(reservationId: widget.reservationId, status: status),
    ));
  }

  Future<void> _close() async {
    final leave = await confirmDialog(context,
        title: '결제를 그만둘까요?',
        message: '결제하지 않으면 잡아 둔 시간은 잠시 후 자동으로 풀려요. 내 예약에서 다시 결제할 수도 있어요.',
        confirm: '그만두기');
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = _remaining;
    final test = widget.order.mode != 'LIVE';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: '닫기', icon: const Icon(Icons.close_rounded), onPressed: _close),
        title: const Text('결제'),
        actions: [
          if (r != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: FmSpace.l),
                child: Text(
                  '${r.inMinutes}:${(r.inSeconds % 60).toString().padLeft(2, '0')} 남음',
                  style: TextStyle(fontWeight: FontWeight.w700, color: r.inSeconds < 60 ? FmColors.danger : FmColors.textSecondary),
                ),
              ),
            ),
        ],
        bottom: test
            ? const PreferredSize(
                preferredSize: Size.fromHeight(32),
                child: Padding(padding: EdgeInsets.only(bottom: FmSpace.s), child: TestModeBadge()),
              )
            : null,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _web),
          if (_loading || _finishing)
            Container(
              color: Colors.white70,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_finishing) ...[
                      const SizedBox(height: FmSpace.m),
                      const Text('결제 결과를 확인하고 있어요'),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
