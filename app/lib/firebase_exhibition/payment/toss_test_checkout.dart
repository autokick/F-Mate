import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:tosspayments_widget_sdk_flutter/model/payment_info.dart';
import 'package:tosspayments_widget_sdk_flutter/model/payment_widget_options.dart';
import 'package:tosspayments_widget_sdk_flutter/payment_widget.dart';
import 'package:tosspayments_widget_sdk_flutter/widgets/agreement.dart';
import 'package:tosspayments_widget_sdk_flutter/widgets/payment_method.dart';

import '../../core/config.dart';
import '../../core/theme.dart';

/// Actual TossPayments sandbox SDK. This is NOT a server-confirmed payment.
/// No financial credentials, live keys or paid-booking flags are stored.
class TossTestCheckout extends StatefulWidget {
  const TossTestCheckout({
    super.key,
    required this.venueName,
    required this.amount,
  });
  final String venueName;
  final int amount;

  @override
  State<TossTestCheckout> createState() => _TossTestCheckoutState();
}

class _TossTestCheckoutState extends State<TossTestCheckout> {
  late final PaymentWidget _paymentWidget;
  late final String _orderId;
  StreamSubscription<Uri>? _links;
  bool _ready = false;
  bool _requesting = false;
  String? _error;

  static String _nonce([int size = 15]) {
    final rng = Random.secure();
    return base64UrlEncode(List.generate(size, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
  }

  @override
  void initState() {
    super.initState();
    _orderId = 'FMATE_DEMO_${_nonce()}';
    if (!AppConfig.tossTestClientKey.startsWith('test_gck_')) {
      _error = '안전하지 않은 결제키: TEST 전용 앱에서는 실제 결제키를 사용할 수 없습니다.';
      return;
    }
    _paymentWidget = PaymentWidget(
      clientKey: AppConfig.tossTestClientKey,
      customerKey: 'visitor_${_nonce()}',
    );
    unawaited(_prepare());
    _links = AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme == 'fmate' && uri.host == 'payment') {
        final redirect = uri.queryParameters['url'];
        if (redirect != null && redirect.isNotEmpty) {
          _paymentWidget.handlePaymentRedirect(redirect);
        }
      }
    });
  }

  Future<void> _prepare() async {
    try {
      await Future.wait([
        _paymentWidget.renderPaymentMethods(
          selector: 'methods',
          amount: Amount(
            value: widget.amount,
            currency: Currency.KRW,
            country: 'KR',
          ),
        ),
        _paymentWidget.renderAgreement(selector: 'agreement'),
      ]);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '토스 테스트 결제 UI를 불러오지 못했어요: $e');
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  Future<void> _pay() async {
    if (!_ready || _requesting) return;
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final result = await _paymentWidget.requestPayment(
        paymentInfo: PaymentInfo(
          orderId: _orderId,
          orderName: '${widget.venueName} 체험 예약',
          appScheme: 'fmate://payment',
        ),
      );
      if (!mounted) return;
      if (result.success != null) {
        final success = result.success!;
        final matching =
            success.orderId == _orderId && success.amount == widget.amount;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _TossTestResult(
              good: matching,
              title: matching ? '토스 테스트 결제 인증 성공' : '주문번호 또는 금액 불일치',
              details: matching
                  ? '실제 토스페이먼츠 테스트 SDK에서 인증 결과를 받았습니다. 다만 서버 승인 API는 연결하지 않았으므로 결제 확정은 아닙니다.'
                  : '토스가 반환한 금액 또는 주문번호가 예상값과 달라 결제 완료로 처리하지 않았습니다.',
            ),
          ),
        );
      } else if (result.pending != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const _TossTestResult(
              good: false,
              title: '테스트 결제 승인 대기',
              details: '서버 승인 대기 상태입니다. 승인되지 않은 결제를 완료로 처리하지 않습니다.',
            ),
          ),
        );
      } else if (result.fail != null) {
        setState(
          () => _error =
              '결제 인증 실패: ${result.fail!.errorMessage} (${result.fail!.errorCode})',
        );
      } else {
        setState(() => _error = '인증 결과가 없어요. 취소했거나 결제창이 닫혔습니다.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '결제 SDK 오류: $e');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeKey = AppConfig.tossTestClientKey.startsWith('test_gck_');
    return Scaffold(
      appBar: AppBar(title: const Text('토스페이먼츠 TEST 결제')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: FmColors.brand.withValues(alpha: .1),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TEST · 실제 청구 0원',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('토스페이먼츠 공식 SDK 테스트 환경입니다. 실제 요금이 청구되지 않습니다.'),
                    SizedBox(height: 5),
                    Text('서버의 최종 승인 API는 미연결이므로 예약금 결제 완료를 의미하지 않습니다.'),
                  ],
                ),
              ),
            ),
            ListTile(
              title: Text(widget.venueName),
              subtitle: const Text('가상 풋살장 · 체험 예약'),
              trailing: Text(
                '${widget.amount}원',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (safeKey) ...[
              PaymentMethodWidget(
                paymentWidget: _paymentWidget,
                selector: 'methods',
              ),
              AgreementWidget(
                paymentWidget: _paymentWidget,
                selector: 'agreement',
              ),
            ],
            if (!_ready && _error == null)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _ready && safeKey && !_requesting ? _pay : null,
              icon: const Icon(Icons.open_in_new),
              label: Text(_requesting ? '토스 인증 처리 중' : '실제 토스 TEST 결제창 열기'),
            ),
            const SizedBox(height: 8),
            const Text(
              '토스페이 노출 여부는 테스트 상점과 단말 환경에 따라 다릅니다. 카드번호 등의 실제 개인정보 입력은 권장하지 않습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TossTestResult extends StatelessWidget {
  const _TossTestResult({
    required this.good,
    required this.title,
    required this.details,
  });
  final bool good;
  final String title;
  final String details;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TEST 인증 결과')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              good ? Icons.verified_outlined : Icons.warning_amber_outlined,
              size: 72,
              color: good ? FmColors.brandDark : Colors.orange,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(details, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text(
              '실제 금전 거래나 승인 완료는 발생하지 않았습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('체험 계속하기'),
            ),
          ],
        ),
      ),
    ),
  );
}
