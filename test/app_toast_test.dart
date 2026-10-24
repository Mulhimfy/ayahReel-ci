import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/app_toast.dart';

/// Every notice in the app is one toast: still a SnackBar underneath —
/// queued, timed and read out by the messenger — with its one action
/// inside it.
void main() {
  Future<void> host(WidgetTester t, SnackBar bar) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(bar),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
  }

  testWidgets('a toast says its message, and goes when its time is up',
      (t) async {
    await host(t, toast('Saved to your gallery', tone: ToastTone.done));
    expect(find.text('Saved to your gallery'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Saved to your gallery'), findsNothing);
  });

  testWidgets('its action runs, and puts the toast away', (t) async {
    var ran = 0;
    await host(
      t,
      toast('Could not save',
          tone: ToastTone.problem,
          actionLabel: 'Report',
          onAction: () => ran++),
    );
    await t.tap(find.text('Report'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(ran, 1);
    expect(find.text('Could not save'), findsNothing);
  });

  testWidgets('a label without an action, or the reverse, shows no button',
      (t) async {
    await host(t, toast('Nothing to do', actionLabel: 'Report'));
    expect(find.text('Report'), findsNothing);
  });
}
