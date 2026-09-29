import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/theme.dart';
import 'package:myaza_kyc_sdk_flutter/src/services/api_service.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/key_people_await_card.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/key_people_await_list.dart';

// ─── The KYB success screen's people list ────────────────────────────────────
//
// Reported on an iPhone (2026-09-29): the cards sat flush against each other,
// and a UBO's line read "Beneficial owner (UBO) · …" because the role text and
// the country name each took half the row, so the role was cut mid-way.

AwaitingPerson _ubo(String id, String name) => AwaitingPerson(
      id: id,
      name: name,
      role: 'beneficial_owner',
      ownershipPct: 30,
      country: 'NG',
      status: 'pending',
      inviteUrl: 'https://example.test/$id',
    );

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [MyazaColorScheme.light]),
      home: Scaffold(
        body: SizedBox(width: 360, child: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('cards in one group have space between them', (tester) async {
    await tester.pumpWidget(_host(KeyPeopleAwaitList(people: [
      _ubo('kp_1', 'Amara Sandbox-Parent'),
      _ubo('kp_2', 'Bola Owner Sandbox'),
    ])));
    await tester.pumpAndSettle();

    final cards = find.byType(KeyPeopleAwaitCard);
    expect(cards, findsNWidgets(2));
    final firstBottom = tester.getRect(cards.at(0)).bottom;
    final secondTop = tester.getRect(cards.at(1)).top;
    expect(secondTop - firstBottom, greaterThanOrEqualTo(MyazaSpacing.sm));
  });

  testWidgets('the role line keeps the role and share whole', (tester) async {
    await tester.pumpWidget(_host(KeyPeopleAwaitList(people: [
      _ubo('kp_1', 'Amara Sandbox-Parent'),
    ])));
    await tester.pumpAndSettle();

    // One piece of text carrying role, share and country, so any cut falls at
    // the end rather than splitting the row in half.
    final line = find.byWidgetPredicate((w) =>
        w is RichText && w.text.toPlainText().contains('30%'));
    expect(line, findsOneWidget);
    // The fix is structural: one paragraph, not two halves. (The test font
    // draws every glyph as a full square, so a width measurement here would
    // say nothing about a phone.)
    final plain = (tester.widget(line) as RichText).text.toPlainText();
    expect(plain, contains('Beneficial owner'));
    expect(plain, contains('Nigeria'));
  });
}
