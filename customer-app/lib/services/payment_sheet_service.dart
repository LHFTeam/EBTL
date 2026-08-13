import 'package:flutter_stripe/flutter_stripe.dart' as stripe;

import '../models/checkout_models.dart';
import 'api_service.dart';

/// How a run of the native payment sheet ended.
enum PaymentSheetOutcome {
  /// The sheet was completed. The order is only paid once the backend has seen
  /// the gateway's webhook, so this still has to be reconciled by polling.
  submitted,

  /// The customer closed the sheet. Nothing was charged and nothing is wrong.
  canceled,

  /// The sheet could not be opened, or the payment did not go through.
  failed,

  /// There is no live payment session to present — an order whose payment
  /// window the backend has already closed, or a gateway that is not
  /// configured.
  unavailable,
}

class PaymentSheetResult {
  final PaymentSheetOutcome outcome;

  /// What to tell the customer, when there is anything worth telling them.
  final String? message;

  const PaymentSheetResult(this.outcome, {this.message});

  bool get isSubmitted => outcome == PaymentSheetOutcome.submitted;
}

/// Opens the native Stripe Payment Sheet (cards, plus Apple Pay / Google Pay
/// where configured) for an already-created payment session.
///
/// Shared by checkout, which creates the session as it places the order, and by
/// the order detail screen, which picks up the session of an order left
/// unpaid. Neither of them decides whether the money arrived: that is the
/// backend's webhook, read back through [pollPaymentStatus].
Future<PaymentSheetResult> presentStripePaymentSheet(
  StripePaymentSession session,
) async {
  final publishableKey = session.publishableKey;

  if (!session.hasClientSecret ||
      publishableKey == null ||
      publishableKey.isEmpty) {
    return const PaymentSheetResult(
      PaymentSheetOutcome.unavailable,
      message: 'Payment could not be started. Please try again.',
    );
  }

  final hasApplePay =
      session.applePayMerchantId != null &&
      session.applePayMerchantId!.isNotEmpty;

  try {
    stripe.Stripe.publishableKey = publishableKey;
    if (hasApplePay) {
      stripe.Stripe.merchantIdentifier = session.applePayMerchantId!;
    }
    await stripe.Stripe.instance.applySettings();

    await stripe.Stripe.instance.initPaymentSheet(
      paymentSheetParameters: stripe.SetupPaymentSheetParameters(
        paymentIntentClientSecret: session.clientSecret,
        merchantDisplayName: session.merchantDisplayName,
        customerId: session.hasCustomer ? session.customerId : null,
        customerEphemeralKeySecret: session.hasCustomer
            ? session.ephemeralKeySecret
            : null,
        applePay: hasApplePay
            ? stripe.PaymentSheetApplePay(
                merchantCountryCode: session.merchantCountry,
              )
            : null,
        googlePay: session.googlePayEnabled
            ? stripe.PaymentSheetGooglePay(
                merchantCountryCode: session.merchantCountry,
                testEnv: session.isTest,
              )
            : null,
      ),
    );

    await stripe.Stripe.instance.presentPaymentSheet();
  } on stripe.StripeException catch (error) {
    // A customer closing the sheet is not an error worth surfacing: nothing was
    // charged and the order is exactly as it was.
    if (error.error.code == stripe.FailureCode.Canceled) {
      return const PaymentSheetResult(PaymentSheetOutcome.canceled);
    }

    return PaymentSheetResult(
      PaymentSheetOutcome.failed,
      message: error.error.localizedMessage ?? 'Payment was not completed.',
    );
  } catch (_) {
    return const PaymentSheetResult(
      PaymentSheetOutcome.failed,
      message: 'Payment was not completed. Please try again.',
    );
  }

  return const PaymentSheetResult(PaymentSheetOutcome.submitted);
}

// Payment reconciliation waits on a Stripe/Geidea webhook reaching the backend.
// On a cold-starting Render instance that can take much longer than the couple
// of seconds it usually does, so poll well past the common case before giving
// up — backing off so we don't hammer the API — and return the last status seen
// if the window is exhausted (the order still settles server-side; the UI just
// can't confirm it live yet).
const Duration _paymentPollBudget = Duration(seconds: 90);
const Duration _paymentPollInitialDelay = Duration(seconds: 2);
const Duration _paymentPollMaxDelay = Duration(seconds: 6);

Future<PaymentStatusResponse> pollPaymentStatus(String orderId) async {
  final deadline = DateTime.now().add(_paymentPollBudget);
  Duration delay = _paymentPollInitialDelay;
  PaymentStatusResponse latest = await ApiService.fetchOrderPaymentStatus(
    orderId: orderId,
  );

  while (!latest.isFinal && DateTime.now().add(delay).isBefore(deadline)) {
    await Future<void>.delayed(delay);
    latest = await ApiService.fetchOrderPaymentStatus(orderId: orderId);

    final Duration next = delay * 1.5;
    delay = next > _paymentPollMaxDelay ? _paymentPollMaxDelay : next;
  }

  return latest;
}
