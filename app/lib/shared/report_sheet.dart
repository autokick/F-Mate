import 'package:flutter/material.dart';

import '../core/services.dart';
import '../core/theme.dart';
import 'widgets.dart';

const Map<String, String> kReportReasons = {
  'SPAM': '스팸·광고',
  'HARASSMENT': '욕설·괴롭힘',
  'HATE': '혐오 표현',
  'SEXUAL': '음란·선정적',
  'VIOLENCE': '폭력적',
  'ILLEGAL': '불법 정보',
  'COPYRIGHT': '저작권 침해',
  'IMPERSONATION': '사칭',
  'FALSE_VENUE_INFO': '허위 구장 정보',
  'OTHER': '기타',
};

/// 신고 시트. targetType: POST | COMMENT | USER | MESSAGE | VENUE
Future<void> showReportSheet(BuildContext context, String targetType, int targetId) async {
  final services = AppScope.read(context);
  String? reason;
  final detail = TextEditingController();
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(
            left: FmSpace.l, right: FmSpace.l, bottom: MediaQuery.of(ctx).viewInsets.bottom + FmSpace.l),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('신고하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: FmSpace.xs),
              const Text('신고 내용은 운영팀만 볼 수 있어요.', style: TextStyle(color: FmColors.textSecondary)),
              const SizedBox(height: FmSpace.m),
              Wrap(
                spacing: FmSpace.s,
                runSpacing: FmSpace.s,
                children: [
                  for (final e in kReportReasons.entries)
                    if (e.key != 'FALSE_VENUE_INFO' || targetType == 'VENUE')
                      ChoiceChip(
                        label: Text(e.value),
                        selected: reason == e.key,
                        onSelected: (_) => setSheet(() => reason = e.key),
                      ),
                ],
              ),
              const SizedBox(height: FmSpace.m),
              TextField(
                controller: detail,
                maxLength: 1000,
                maxLines: 3,
                minLines: 1,
                decoration: fmInputDecoration(label: '자세한 내용 (선택)'),
              ),
              const SizedBox(height: FmSpace.s),
              LoadingButton(
                label: '신고 제출',
                onPressed: reason == null
                    ? null
                    : () async {
                        try {
                          await services.social.report(targetType, targetId, reason!, detail.text.trim());
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        } catch (e) {
                          if (ctx.mounted) showError(ctx, e);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  detail.dispose();
  if (submitted == true && context.mounted) showFmSnack(context, '신고가 접수되었어요. 검토 후 조치할게요');
}
