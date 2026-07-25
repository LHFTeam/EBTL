import '../core/utils/formatters.dart';
import '../core/utils/json_helpers.dart';

/// The referral hub payload returned by `GET /api/customer/referrals` and
/// `POST /api/customer/referrals/apply`.
class ReferralHub {
  final bool programActive;
  final String? code;
  final String? shareMessage;
  final double creditBalance;
  final String currency;
  final ReferralStats stats;
  final ReferralRewards rewards;
  final List<String> howItWorks;
  final String? terms;

  const ReferralHub({
    required this.programActive,
    required this.code,
    required this.shareMessage,
    required this.creditBalance,
    required this.currency,
    required this.stats,
    required this.rewards,
    required this.howItWorks,
    required this.terms,
  });

  factory ReferralHub.fromJson(Map<String, dynamic> json) {
    final credit = asMap(json['credit']);
    return ReferralHub(
      programActive: readBool(json['program_active'], fallback: true),
      code: readString(json['code']).isEmpty ? null : readString(json['code']),
      shareMessage: readString(json['share_message']).isEmpty
          ? null
          : readString(json['share_message']),
      creditBalance: readDouble(credit['balance']) ?? 0,
      currency: readString(credit['currency'], fallback: 'EGP'),
      stats: ReferralStats.fromJson(asMap(json['stats'])),
      rewards: ReferralRewards.fromJson(asMap(json['rewards'])),
      howItWorks: readStringList(json['how_it_works']),
      terms: readString(json['terms']).isEmpty ? null : readString(json['terms']),
    );
  }

  String get creditBalanceLabel => formatMoney(creditBalance, currency);
  bool get hasCredit => creditBalance > 0;
}

class ReferralStats {
  final int invited;
  final int pending;
  final int rewarded;
  final double creditEarned;

  const ReferralStats({
    required this.invited,
    required this.pending,
    required this.rewarded,
    required this.creditEarned,
  });

  factory ReferralStats.fromJson(Map<String, dynamic> json) {
    return ReferralStats(
      invited: readInt(json['invited']),
      pending: readInt(json['pending']),
      rewarded: readInt(json['rewarded']),
      creditEarned: readDouble(json['credit_earned']) ?? 0,
    );
  }
}

class ReferralRewards {
  final double referrerRewardAmount;
  final String refereeRewardLabel;
  final double minQualifyingOrderValue;
  final String currency;

  const ReferralRewards({
    required this.referrerRewardAmount,
    required this.refereeRewardLabel,
    required this.minQualifyingOrderValue,
    required this.currency,
  });

  factory ReferralRewards.fromJson(Map<String, dynamic> json) {
    return ReferralRewards(
      referrerRewardAmount: readDouble(json['referrer_reward_amount']) ?? 0,
      refereeRewardLabel: readString(json['referee_reward_label'], fallback: 'a discount'),
      minQualifyingOrderValue: readDouble(json['min_qualifying_order_value']) ?? 0,
      currency: readString(json['currency'], fallback: 'EGP'),
    );
  }

  String get referrerRewardLabel => formatMoney(referrerRewardAmount, currency);
}
