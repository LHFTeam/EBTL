// The Notifications quick link badges the unread count that came down with the
// profile payload, but the profile is only fetched when the tab is first built.
// Reading the notifications marks them read while the profile stays mounted, so
// the tile has to follow the shell's live count instead of the fetched one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ebtl_customer_app/features/profile/widgets/profile_widgets.dart';
import 'package:ebtl_customer_app/models/profile_models.dart';

const _links = [
  ProfileQuickLink(
    key: 'addresses',
    title: 'Addresses',
    subtitle: 'Manage your delivery addresses',
    endpoint: '/api/customer/addresses',
    enabled: true,
    placeholder: false,
    count: 2,
  ),
  ProfileQuickLink(
    key: 'favorite_spirits',
    title: 'My Spirits',
    subtitle: 'The bottles you keep at hand',
    endpoint: '/api/customer/spirits',
    enabled: true,
    placeholder: false,
    count: 2,
  ),
  ProfileQuickLink(
    key: 'notifications',
    title: 'Notifications',
    subtitle: '3 unread',
    endpoint: '/api/customer/notifications',
    enabled: true,
    placeholder: false,
    count: 3,
  ),
];

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('ProfileQuickLinksSection', () {
    testWidgets('badges the live unread count, not the fetched one', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileQuickLinksSection(
            links: _links,
            onTapLink: (_) {},
            unreadNotificationCount: 5,
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);
      expect(find.text('5 unread'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      expect(find.text('3 unread'), findsNothing);
    });

    testWidgets('drops the badge once the notifications have been read', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileQuickLinksSection(
            links: _links,
            onTapLink: (_) {},
            unreadNotificationCount: 0,
          ),
        ),
      );

      expect(find.text('3'), findsNothing);
      expect(find.text('3 unread'), findsNothing);
      expect(find.text('Order updates and pickup alerts'), findsOneWidget);
    });

    testWidgets('leaves the other links alone', (tester) async {
      await tester.pumpWidget(
        wrap(
          ProfileQuickLinksSection(
            links: _links,
            onTapLink: (_) {},
            unreadNotificationCount: 0,
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('The bottles you keep at hand'), findsOneWidget);
    });

    // Delivery has not launched, so the addresses tile is hidden even when the
    // backend keeps sending it.
    testWidgets('hides the addresses link', (tester) async {
      await tester.pumpWidget(
        wrap(
          ProfileQuickLinksSection(
            links: _links,
            onTapLink: (_) {},
            unreadNotificationCount: 0,
          ),
        ),
      );

      expect(find.text('Addresses'), findsNothing);
      expect(find.text('Manage your delivery addresses'), findsNothing);
    });

    testWidgets('hides the addresses link in the fallback list', (tester) async {
      await tester.pumpWidget(
        wrap(
          ProfileQuickLinksSection(
            links: const [],
            onTapLink: (_) {},
            unreadNotificationCount: 0,
          ),
        ),
      );

      expect(find.text('Addresses'), findsNothing);
      expect(find.text('My Spirits'), findsOneWidget);
    });

    testWidgets('keeps a non-unread subtitle when nothing is unread', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileQuickLinksSection(
            links: const [
              ProfileQuickLink(
                key: 'notifications',
                title: 'Notifications',
                subtitle: 'Order updates and pickup alerts',
                endpoint: '/api/customer/notifications',
                enabled: true,
                placeholder: false,
                count: 0,
              ),
            ],
            onTapLink: (_) {},
            unreadNotificationCount: 0,
          ),
        ),
      );

      expect(find.text('Order updates and pickup alerts'), findsOneWidget);
    });
  });
}
