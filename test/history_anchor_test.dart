import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lbjconsole/ui/anchored_sliver.dart';

class ItemData {
  ItemData(this.id, this.subs, this.tracked);

  final String id;
  final List<String> subs;
  final String? tracked;
}

class Harness extends StatefulWidget {
  const Harness({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  final List<ItemData> items = <ItemData>[
    for (int i = 0; i < 20; i++)
      i == 3
          ? ItemData('item3', <String>['s0', 's1', 's2', 's3', 's4'], 's2')
          : ItemData('item$i', <String>[], null),
  ];
  final Map<String, GlobalKey> subKeys = <String, GlobalKey>{};

  GlobalKey keyFor(String sub) {
    return subKeys.putIfAbsent(sub, () => GlobalKey());
  }

  void moveTrackedToTopWithInsert() {
    setState(() {
      final ItemData item = items.removeAt(3);
      item.subs.insert(item.subs.indexOf('s2'), 'sNew');
      items.insert(0, item);
    });
  }

  void insertNewTop() {
    setState(() {
      items.insert(0, ItemData('newTop', <String>[], null));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredListView(
      itemCount: items.length,
      itemKeyAt: (int index) => items[index].id,
      itemBuilder: (BuildContext context, int index) {
        final ItemData item = items[index];
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
          ],
        );
      },
      scrollController: widget.controller,
      subKeyAt: (int index) {
        final String? tracked = items[index].tracked;
        return tracked == null ? null : keyFor(tracked);
      },
    );
  }
}

double subDy(WidgetTester tester, GlobalKey key) {
  final Rect rect = tester.getRect(find.byKey(key));
  final Rect viewport = tester.getRect(find.byType(Viewport));
  return rect.top - viewport.top;
}

void main() {
  testWidgets('anchor sub row keeps dy when its item moves to top', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Harness(controller: controller)),
      ),
    );
    final HarnessState state = tester.state<HarnessState>(
      find.byType(Harness),
    );
    final GlobalKey subKey = state.keyFor('s2');
    controller.jumpTo(150);
    await tester.pump();
    final double dyBefore = subDy(tester, subKey);
    expect(controller.offset, 150);

    state.moveTrackedToTopWithInsert();
    await tester.pump();

    final double dyAfter = subDy(tester, subKey);
    expect((dyAfter - dyBefore).abs(), lessThanOrEqualTo(0.5));
    expect(controller.offset, isNot(150));
    expect((controller.offset - 60).abs(), lessThanOrEqualTo(0.5));
  });

  testWidgets('anchor follows after plain scroll when item inserted above', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Harness(controller: controller)),
      ),
    );
    final HarnessState state = tester.state<HarnessState>(
      find.byType(Harness),
    );
    final GlobalKey subKey = state.keyFor('s2');
    controller.jumpTo(150);
    await tester.pump();
    final double dyBefore = subDy(tester, subKey);
    expect(controller.offset, 150);

    state.insertNewTop();
    await tester.pump();

    final double dyAfter = subDy(tester, subKey);
    expect((dyAfter - dyBefore).abs(), lessThanOrEqualTo(0.5));
    expect((controller.offset - 190).abs(), lessThanOrEqualTo(0.5));
  });
}
