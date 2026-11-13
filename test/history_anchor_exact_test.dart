import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lbjconsole/ui/anchored_sliver.dart';

class TopHarness extends StatefulWidget {
  const TopHarness({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<TopHarness> createState() => TopHarnessState();
}

class TopHarnessState extends State<TopHarness> {
  final List<String> items = <String>[for (int i = 0; i < 30; i++) 'item$i'];

  void insertTop() {
    setState(() {
      items.insert(0, 'newTop');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredListView(
      itemCount: items.length,
      itemKeyAt: (int index) => items[index],
      itemBuilder: (BuildContext context, int index) {
        return SizedBox(height: 40, child: Text(items[index]));
      },
      scrollController: widget.controller,
    );
  }
}

class ExactItem {
  ExactItem(this.id, this.height, {this.header = 0, this.subHeight = 0});

  final String id;
  final double height;
  final double header;
  final double subHeight;

  bool get tracked => subHeight > 0;
  double get tail => height - header - subHeight;
}

class ExactHarness extends StatefulWidget {
  const ExactHarness({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<ExactHarness> createState() => ExactHarnessState();
}

class ExactHarnessState extends State<ExactHarness> {
  static const List<double> heights = <double>[
    15,
    90,
    25,
    140,
    35,
    60,
    200,
    45,
    30,
    110,
    20,
    75,
    160,
    40,
    55,
    95,
    28,
    130,
    65,
    85,
  ];
  static const double insertedHeight = 333;

  final List<ExactItem> items = <ExactItem>[
    for (int i = 0; i < heights.length; i++)
      i == 3
          ? ExactItem('item3', heights[3], header: 50, subHeight: 30)
          : ExactItem('item$i', heights[i]),
  ];
  final Map<String, GlobalKey> subKeys = <String, GlobalKey>{};

  GlobalKey keyFor(String sub) {
    return subKeys.putIfAbsent(sub, () => GlobalKey());
  }

  void insertNewTop() {
    setState(() {
      items.insert(0, ExactItem('newTop', insertedHeight));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredListView(
      itemCount: items.length,
      itemKeyAt: (int index) => items[index].id,
      itemBuilder: (BuildContext context, int index) {
        final ExactItem item = items[index];
        if (!item.tracked) {
          return SizedBox(height: item.height, child: Text(item.id));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(height: item.header, child: Text(item.id)),
            Container(
              key: keyFor('sub'),
              height: item.subHeight,
              color: Colors.blueGrey,
            ),
            SizedBox(height: item.tail),
          ],
        );
      },
      scrollController: widget.controller,
      subKeyAt: (int index) {
        return items[index].tracked ? keyFor('sub') : null;
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
  testWidgets('top stays at top when new item inserted at head', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TopHarness(controller: controller)),
      ),
    );
    final TopHarnessState state = tester.state<TopHarnessState>(
      find.byType(TopHarness),
    );
    expect(controller.offset, 0);

    state.insertTop();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.offset, 0);
    final Rect viewport = tester.getRect(find.byType(Viewport));
    final Rect newTop = tester.getRect(find.text('newTop'));
    expect((newTop.top - viewport.top).abs(), lessThanOrEqualTo(0.5));
    final Rect oldHead = tester.getRect(find.text('item0'));
    expect((oldHead.top - viewport.top - 40).abs(), lessThanOrEqualTo(0.5));
  });

  testWidgets('irregular heights anchor dy and offset delta are exact', (
    WidgetTester tester,
  ) async {
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExactHarness(controller: controller)),
      ),
    );
    final ExactHarnessState state = tester.state<ExactHarnessState>(
      find.byType(ExactHarness),
    );
    final GlobalKey subKey = state.keyFor('sub');
    controller.jumpTo(200);
    await tester.pump();
    expect(controller.offset, 200);
    final double dyBefore = subDy(tester, subKey);
    expect((dyBefore - -20).abs(), lessThanOrEqualTo(0.5));

    state.insertNewTop();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final double dyAfter = subDy(tester, subKey);
    expect((dyAfter - dyBefore).abs(), lessThanOrEqualTo(0.5));
    expect(
      ((controller.offset - 200) - ExactHarnessState.insertedHeight).abs(),
      lessThanOrEqualTo(0.5),
    );
  });
}
