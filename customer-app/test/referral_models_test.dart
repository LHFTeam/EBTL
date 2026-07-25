// Model tests for the referral hub payload. The backend payload is treated as
// untrusted, so the fromJson factories must survive missing and mistyped
// fields with safe defaults.

import 'package:flutter_test/flutter_test.dart';

import 'package:ebtl_customer_app/models/referral_models.dart';
import 'package:ebtl_customer_app/models/checkout_models.dart';

void main() {
  group('ReferralHub.fromJson', () {
    test('parses a full payload', () {
      final hub = ReferralHub.fromJson(const {
        'program_active': true,
        'code': 'EBTL-ABCDE',
        'share_message': 'Use my code EBTL-ABCDE!',
        'credit': {'balance': 150.5, 'currency': 'EGP'},
        'stats': {
          'invited': 4,
          'pending': 1,
          'rewarded': 3,
          'credit_earned': 300,
        },
        'rewards': {
          'referrer_reward_amount': 100,
          'referee_reward_label': 'EGP 75 off',
          'min_qualifying_order_value': 200,
          'currency': 'EGP',
        },
        'how_it_works': ['Share your code.', 'They save.', 'You earn.'],
        'terms': 'Reward granted after first paid order.',
      });

      expect(hub.programActive, true);
      expect(hub.code, 'EBTL-ABCDE');
      expect(hub.shareMessage, 'Use my code EBTL-ABCDE!');
      expect(hub.creditBalance, 150.5);
      expect(hub.hasCredit, true);
      expect(hub.stats.invited, 4);
      expect(hub.stats.pending, 1);
      expect(hub.stats.rewarded, 3);
      expect(hub.rewards.referrerRewardAmount, 100);
      expect(hub.rewards.refereeRewardLabel, 'EGP 75 off');
      expect(hub.howItWorks, hasLength(3));
      expect(hub.terms, 'Reward granted after first paid order.');
    });

    test('falls back safely on an empty payload', () {
      final hub = ReferralHub.fromJson(const {});

      expect(hub.programActive, true);
      expect(hub.code, isNull);
      expect(hub.shareMessage, isNull);
      expect(hub.creditBalance, 0);
      expect(hub.hasCredit, false);
      expect(hub.stats.invited, 0);
      expect(hub.rewards.refereeRewardLabel, 'a discount');
      expect(hub.howItWorks, isEmpty);
      expect(hub.terms, isNull);
    });
  });

  group('CheckoutSummary referral + credit lines', () {
    test('parses referral discount and applied store credit', () {
      final summary = CheckoutSummary.fromJson(const {
        'subtotal_ex_vat': 500,
        'vat_amount': 70,
        'subtotal_inc_vat': 570,
        'discount_amount': 0,
        'referral_discount_amount': 75,
        'credit_applied': 100,
        'delivery_fee': 30,
        'total_amount': 425,
        'currency': 'EGP',
        'vat_included': true,
      });

      expect(summary.hasReferralDiscount, true);
      expect(summary.referralDiscountAmount, 75);
      expect(summary.hasCreditApplied, true);
      expect(summary.creditApplied, 100);
      expect(summary.totalAmount, 425);
    });

    test('defaults referral + credit to zero when absent', () {
      final summary = CheckoutSummary.fromJson(const {
        'subtotal_inc_vat': 200,
        'total_amount': 200,
      });

      expect(summary.hasReferralDiscount, false);
      expect(summary.referralDiscountAmount, 0);
      expect(summary.hasCreditApplied, false);
      expect(summary.creditApplied, 0);
    });
  });
}
