import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lbjconsole/ui/anchored_sliver.dart';

class StressItem {
  StressItem(this.id);

  final String id;
  final List<String> subs = <String>[];
  String? tracked;
  bool expanded = false;
}

class ItemRow extends StatelessWidget {
  const ItemRow({super.key, required this.item, required this.keyFor});

  final StressItem item;
  final GlobalKey Function(String) keyFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: 40, child: Text(item.id)),
        for (final String sub in item.subs)
          Container(
            key: keyFor(sub),
            height: 30,
            color: Colors.blueGrey,
            child: Text(sub),
          ),
        if (item.expanded)
          Container(height: 300, color: Colors.orange, child: const Text('expanded')),
      ],
    );
  }
}

class StressHarness extends StatefulWidget {
  const StressHarness({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<StressHarness> createState() => StressHarnessState();
}

class StressHarnessState extends State<StressHarness> {
  final List<StressItem> items = <StressItem>[
    for (int i = 0; i < 30; i++) StressItem('item$i'),
  ];
  final Map<String, GlobalKey> subKeys = <String, GlobalKey>{};

  GlobalKey keyFor(String sub) {
    return subKeys.putIfAbsent(sub, () => GlobalKey());
  }

  void replaceItems(List<StressItem> next) {
    setState(() {
      items
        ..clear()
        ..addAll(next);
    });
  }

  void removeIds(Set<String> ids) {
    setState(() {
      items.removeWhere((StressItem item) => ids.contains(item.id));
    });
  }

  void insertTop(List<StressItem> next) {
    setState(() {
      items.insertAll(0, next);
    });
  }

  void toggleExpanded(String id) {
    setState(() {
      final StressItem item = items.firstWhere(
        (StressItem entry) => entry.id == id,
      );
      item.expanded = !item.expanded;
    });
  }

  void addTrackedGroup() {
    setState(() {
      items[3].subs.addAll(<String>['s0', 's1', 's2', 's3', 's4']);
      items[3].tracked = 's2';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredListView(
      itemCount: items.length,
      itemKeyAt: (int index) => items[index].id,
      itemBuilder: (BuildContext context, int index) {
        return ItemRow(item: items[index], keyFor: keyFor);
      },
      scrollController: widget.controller,
      subKeyAt: (int index) {
        final String? tracked = items[index].tracked;
        return tracked == null ? null : keyFor(tracked);
      },
    );
  }
}

Future<StressHarnessState> boot(
  WidgetTester tester,
  ScrollController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StressHarness(controller: controller)),
    ),
  );
  return tester.state<StressHarnessState>(find.byType(StressHarness));
}

void expectPainted(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final Rect viewport = tester.getRect(find.byType(Viewport));
  bool anyVisible = false;
  for (final Element element in find.byType(ItemRow).evaluate()) {
    final RenderObject? renderObject = element.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.attached) {
      final Rect rect =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (rect.overlaps(viewport)) {
        anyVisible = true;
      }
    }
  }
  expect(anyVisible, isTrue);
}

void main() {
  testWidgets('case1 shorter list replaces while scrolled deep', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expectPainted(tester);

    state.replaceItems(<StressItem>[
      for (int i = 0; i < 5; i++) StressItem('short$i'),
    ]);
    await tester.pump();

    expectPainted(tester);
  });

  testWidgets('case2 anchor item deleted while scrolled deep', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    controller.jumpTo(320);
    await tester.pump();
    expectPainted(tester);

    state.removeIds(<String>{'item8'});
    await tester.pump();

    expectPainted(tester);
  });

  testWidgets('case3 three items inserted at head while scrolled mid', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    controller.jumpTo(320);
    await tester.pump();
    expectPainted(tester);

    state.insertTop(<StressItem>[
      StressItem('new0'),
      StressItem('new1'),
      StressItem('new2'),
    ]);
    await tester.pump();

    expectPainted(tester);
  });

  testWidgets('case4 cleared then refilled while scrolled deep', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expectPainted(tester);

    state.replaceItems(<StressItem>[]);
    await tester.pump();
    expect(tester.takeException(), isNull);

    state.replaceItems(<StressItem>[
      for (int i = 0; i < 20; i++) StressItem('reload$i'),
    ]);
    await tester.pump();

    expectPainted(tester);
  });

  testWidgets('case5 mid item expands collapses expands', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    controller.jumpTo(200);
    await tester.pump();
    expectPainted(tester);

    state.toggleExpanded('item10');
    await tester.pump();
    expect(tester.takeException(), isNull);

    state.toggleExpanded('item10');
    await tester.pump();
    expect(tester.takeException(), isNull);

    state.toggleExpanded('item10');
    await tester.pump();

    expectPainted(tester);
  });

  testWidgets('case6 tail items deleted while scrolled to bottom', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expectPainted(tester);

    state.removeIds(<String>{for (int i = 10; i < 30; i++) 'item$i'});
    await tester.pump();

    expectPainted(tester);
  });

  testWidgets('case7 all keys replaced while scrolled deep', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expectPainted(tester);

    state.replaceItems(<StressItem>[
      for (int i = 0; i < 30; i++) StressItem('fresh$i'),
    ]);
    await tester.pump();

    expectPainted(tester);
  });

  testWidgets('case8 tracked sub group deleted next group takes over', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    final StressHarnessState state = await boot(tester, controller);
    state.addTrackedGroup();
    await tester.pump();
    controller.jumpTo(150);
    await tester.pump();
    expectPainted(tester);

    state.removeIds(<String>{'item3'});
    await tester.pump();

    expectPainted(tester);
  });
}
