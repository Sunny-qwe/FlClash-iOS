import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/current_outbound.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';

class _StoppedIps extends OutboundIpProbe {
  @override
  RoutedProbeState<String, IpInfo> build() => const RoutedProbeState();

  @override
  void watch(String target) {}

  @override
  void unwatch(String target) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final path in [
      '/System/Library/Fonts/PingFang.ttc',
      '/System/Library/Fonts/STHeiti Medium.ttc',
      'C:/Windows/Fonts/msyh.ttc',
    ]) {
      final font = File(path);
      if (!font.existsSync()) continue;
      final loader = FontLoader('ReferenceFont')
        ..addFont(font.readAsBytes().then(ByteData.sublistView));
      await loader.load();
      break;
    }
  });

  for (final brightness in Brightness.values) {
  for (final running in [false, true]) {
  testWidgets('reference status card preserves the wave: $brightness running=$running', (tester) async {
    final capture = GlobalKey();
    await tester.pumpWidget(TestApp(
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(fontFamily: 'ReferenceFont', brightness: brightness),
      darkTheme: ThemeData(fontFamily: 'ReferenceFont', brightness: brightness),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      overrides: [
        profilesProvider.overrideWithValue(const [
          Profile(id: 1, autoUpdateDuration: Duration.zero),
        ]),
        runTimeProvider.overrideWithBuild((_, _) => running ? 1 : null),
        suspendProvider.overrideWithValue(false),
        rootAccessProvider.overrideWith((_) async => false),
        outboundIpProbeProvider.overrideWith(_StoppedIps.new),
      ],
      child: HostScaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: RepaintBoundary(
            key: capture,
            child: const SizedBox(
              width: 356,
              child: DashboardDensityScope(
                density: DashboardDensity.mobile,
                scale: 1,
                child: CurrentOutboundCard(),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(commonDuration);
    expect(tester.takeException(), isNull);
    final wave = tester.widget<CustomPaint>(find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter.runtimeType.toString() == '_StatusWavePainter',
    ));
    await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    wave.painter!.paint(Canvas(recorder), const Size(589, 302));
    final picture = recorder.endRecording();
    final mask = await picture.toImage(589, 302);
    final pixels = (await mask.toByteData())!;
    int alpha(double x, double y) => pixels.getUint8(((y * 301).round() * 589 + (x * 588).round()) * 4 + 3);
    expect(alpha(0.9, 0.5), 255);
    expect(alpha(0.85, 0.98), 0);
    expect(alpha(0.7, 0.94), 0);
    expect(alpha(0.4, 0.5), 0);
    if (running) {
      final offset = ((0.5 * 301).round() * 589 + (0.9 * 588).round()) * 4;
      expect([for (var i = 0; i < 4; i++) pixels.getUint8(offset + i)], [228, 235, 251, 255]);
    }
    mask.dispose();
    picture.dispose();
      final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      expect(boundary.size.height, lessThan(220));
      final image = await boundary.toImage(pixelRatio: 589 / 356);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final suffix = running ? '-running-${brightness.name}' : '-${brightness.name}';
      final output = File('build/verification/status-card$suffix.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
  }
  }
}
