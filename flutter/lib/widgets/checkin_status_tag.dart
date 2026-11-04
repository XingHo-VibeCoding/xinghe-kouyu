import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

/// 签到状态标签：进行中（青绿底）/ 已结束（灰底）。
class CheckinStatusTag extends StatelessWidget {
  const CheckinStatusTag({super.key, required this.ended});

  final bool ended;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpaceSM, vertical: kSpaceXXS),
      decoration: BoxDecoration(
        color: ended ? kBorder : kTealSoft,
        borderRadius: BorderRadius.circular(kRadiusBtn),
      ),
      child: Text(
        ended ? '已结束' : '进行中',
        style: TextStyle(
          fontSize: kFontCaption,
          color: ended ? kTextHint : kTeal,
          fontWeight: kWeightMedium,
        ),
      ),
    );
  }
}
