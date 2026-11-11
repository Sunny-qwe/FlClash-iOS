import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/views/config/local_network.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('local protection edits real routes and preserves other exclusions', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(patchClashConfigProvider.notifier).value = const PatchClashConfig(
      tun: Tun(routeExcludeAddress: ['192.0.2.0/24']),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: LocalNetworkView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protect local pairing'), findsOneWidget);
    await tester.tap(find.text('Protect local pairing'));
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).tun.routeExcludeAddress, containsAll([
      '192.0.2.0/24', '127.0.0.0/8', '10.7.0.0/24', '::1/128',
    ]));
    await tester.tap(find.text('Protect local pairing'));
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).tun.routeExcludeAddress, ['192.0.2.0/24']);
  });
}
