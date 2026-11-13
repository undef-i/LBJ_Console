import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class AnchoredListView extends StatefulWidget {
  const AnchoredListView({
    super.key,
    required this.itemCount,
    required this.itemKeyAt,
    required this.itemBuilder,
    required this.scrollController,
    this.subKeyAt,
    this.cacheExtent = 250,
  });

  final int itemCount;
  final String Function(int index) itemKeyAt;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController scrollController;
  final GlobalKey? Function(int index)? subKeyAt;
  final double cacheExtent;

  @override
  State<AnchoredListView> createState() => _AnchoredListViewState();
}

class _AnchoredListViewState extends State<AnchoredListView> {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: widget.scrollController,
      scrollCacheExtent: ScrollCacheExtent.pixels(widget.cacheExtent),
      slivers: <Widget>[
        _AnchoredSliver(
          itemCount: widget.itemCount,
          itemKeyAt: widget.itemKeyAt,
          subKeyAt: widget.subKeyAt,
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) => KeyedSubtree(
              key: ValueKey<String>(widget.itemKeyAt(index)),
              child: widget.itemBuilder(context, index),
            ),
            childCount: widget.itemCount,
            findChildIndexCallback: (Key key) {
              final String value = (key as ValueKey<String>).value;
              for (int i = 0; i < widget.itemCount; i++) {
                if (widget.itemKeyAt(i) == value) {
                  return i;
                }
              }
              return null;
            },
          ),
        ),
      ],
    );
  }
}

class _AnchoredSliver extends SliverMultiBoxAdaptorWidget {
  const _AnchoredSliver({
    required this.itemCount,
    required this.itemKeyAt,
    required this.subKeyAt,
    required super.delegate,
  });

  final int itemCount;
  final String Function(int index) itemKeyAt;
  final GlobalKey? Function(int index)? subKeyAt;

  @override
  RenderAnchoredSliver createRenderObject(BuildContext context) {
    final SliverMultiBoxAdaptorElement element =
        context as SliverMultiBoxAdaptorElement;
    return RenderAnchoredSliver(
      childManager: element,
      itemCount: itemCount,
      itemKeyAt: itemKeyAt,
      subKeyAt: subKeyAt,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAnchoredSliver renderObject,
  ) {
    renderObject
      ..itemCount = itemCount
      ..itemKeyAt = itemKeyAt
      ..subKeyAt = subKeyAt;
  }
}

typedef _ChainEntry = ({int index, double offset, double extent});

class RenderAnchoredSliver extends RenderSliverMultiBoxAdaptor {
  RenderAnchoredSliver({
    required super.childManager,
    required int itemCount,
    required String Function(int index) itemKeyAt,
    required GlobalKey? Function(int index)? subKeyAt,
  }) : _itemCount = itemCount,
       _itemKeyAt = itemKeyAt,
       _subKeyAt = subKeyAt;

  int _itemCount;
  String Function(int index) _itemKeyAt;
  GlobalKey? Function(int index)? _subKeyAt;

  final Map<String, double> _extents = <String, double>{};
  List<String>? _lastKeys;
  String? _anchorKey;
  GlobalKey? _anchorSubKey;
  double _anchorDy = 0;
  double _anchorSubOffset = 0;
  int _anchorIndexHint = 0;

  int get itemCount => _itemCount;
  set itemCount(int value) {
    if (_itemCount == value) {
      return;
    }
    _itemCount = value;
    markNeedsLayout();
  }

  String Function(int index) get itemKeyAt => _itemKeyAt;
  set itemKeyAt(String Function(int index) value) {
    if (_itemKeyAt == value) {
      return;
    }
    _itemKeyAt = value;
    markNeedsLayout();
  }

  GlobalKey? Function(int index)? get subKeyAt => _subKeyAt;
  set subKeyAt(GlobalKey? Function(int index)? value) {
    if (_subKeyAt == value) {
      return;
    }
    _subKeyAt = value;
    markNeedsLayout();
  }

  double _extentOf(RenderBox child) {
    return constraints.axis == Axis.vertical
        ? child.size.height
        : child.size.width;
  }

  bool _keysEqual(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  RenderBox? _childAt(int index) {
    RenderBox? child = firstChild;
    while (child != null) {
      if (indexOf(child) == index) {
        return child;
      }
      child = childAfter(child);
    }
    return null;
  }

  int _childCount() {
    int count = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      count += 1;
      child = childAfter(child);
    }
    return count;
  }

  double _childOffset(RenderBox child) {
    return (child.parentData as SliverMultiBoxAdaptorParentData).layoutOffset ??
        0;
  }

  void _setChildOffset(RenderBox child, double value) {
    (child.parentData as SliverMultiBoxAdaptorParentData).layoutOffset = value;
  }

  double _layoutChild(
    RenderBox child,
    int index,
    List<String> keys,
    BoxConstraints childConstraints,
  ) {
    child.layout(childConstraints, parentUsesSize: true);
    final double extent = _extentOf(child);
    _extents[keys[index]] = extent;
    return extent;
  }

  double _recordExtent(RenderBox child, int index, List<String> keys) {
    final double extent = _extentOf(child);
    _extents[keys[index]] = extent;
    return extent;
  }

  double? _measureSub(RenderBox item, GlobalKey key) {
    final BuildContext? context = key.currentContext;
    if (context == null || !context.mounted) {
      return null;
    }
    final RenderObject? target = (context as Element).renderObject;
    if (target is! RenderBox || !target.hasSize || !target.attached) {
      return null;
    }
    double? found;
    void walk(RenderObject node, Offset acc) {
      if (found != null) {
        return;
      }
      if (node == target) {
        found = constraints.axis == Axis.vertical ? acc.dy : acc.dx;
        return;
      }
      if (node is RenderBox) {
        node.visitChildren((RenderObject child) {
          if (child is RenderBox) {
            final ParentData? data = child.parentData;
            final Offset offset = data is BoxParentData
                ? data.offset
                : Offset.zero;
            walk(child, acc + offset);
          }
        });
      }
    }

    walk(item, Offset.zero);
    return found;
  }

  RenderBox? _obtainChild(int index) {
    final RenderBox? existing = _childAt(index);
    if (existing != null) {
      return existing;
    }
    final int existingCount = _childCount();
    if (existingCount > 0) {
      collectGarbage(existingCount, 0);
    }
    if (!addInitialChild(index: index, layoutOffset: 0)) {
      return null;
    }
    return firstChild;
  }

  void _degenerate(List<String> keys) {
    double average = 0;
    if (_extents.isNotEmpty) {
      double sum = 0;
      for (final double value in _extents.values) {
        sum += value;
      }
      average = sum / _extents.length;
    }
    double total = 0;
    for (final String key in keys) {
      total += _extents[key] ?? average;
    }
    childManager.didFinishLayout();
    geometry = SliverGeometry(
      scrollExtent: total,
      paintExtent: 0,
      maxPaintExtent: total,
    );
  }

  void _captureOne(List<String> keys, int index, double scrollOffset) {
    final RenderBox? child = _childAt(index);
    if (child == null) {
      return;
    }
    final double offset = _childOffset(child);
    final GlobalKey? subKey = _subKeyAt?.call(index);
    final double? subOffset = subKey == null
        ? null
        : _measureSub(child, subKey);
    _anchorKey = keys[index];
    _anchorIndexHint = index;
    if (subOffset != null) {
      _anchorSubKey = subKey;
      _anchorSubOffset = subOffset;
      _anchorDy = offset + subOffset - scrollOffset;
    } else {
      _anchorSubKey = null;
      _anchorSubOffset = 0;
      _anchorDy = offset - scrollOffset;
    }
  }

  void _captureAnchor(
    List<String> keys,
    double scrollOffset,
    int firstIndex,
    int lastIndex,
    bool topMode,
  ) {
    if (topMode) {
      _captureOne(keys, 0, scrollOffset);
      return;
    }
    for (int i = firstIndex; i <= lastIndex; i++) {
      final RenderBox? child = _childAt(i);
      if (child == null) {
        continue;
      }
      final double offset = _childOffset(child);
      if (offset + _extentOf(child) > scrollOffset || i == lastIndex) {
        _captureOne(keys, i, scrollOffset);
        return;
      }
    }
  }

  void _finishFromChain(
    List<String> keys,
    double scrollOffset,
    double cacheStart,
    double targetEnd,
    List<_ChainEntry> chain,
    bool topMode,
  ) {
    final int count = keys.length;
    _ChainEntry firstKept = chain.last;
    for (final _ChainEntry entry in chain) {
      if (entry.offset + entry.extent > cacheStart) {
        firstKept = entry;
        break;
      }
    }
    final _ChainEntry lastEntry = chain.last;
    final _ChainEntry headEntry = chain.first;
    final int chainFirstIndex = firstKept.index;
    final double chainFirstOffset = firstKept.offset;
    final int chainLastIndex = lastEntry.index;
    final double chainLastEndOffset = lastEntry.offset + lastEntry.extent;

    final int leadingGarbage = calculateLeadingGarbage(
      firstIndex: chainFirstIndex,
    );
    final int trailingGarbage = calculateTrailingGarbage(
      lastIndex: chainLastIndex,
    );
    if (leadingGarbage > 0 || trailingGarbage > 0) {
      collectGarbage(leadingGarbage, trailingGarbage);
    }

    final double paintExtent = calculatePaintOffset(
      constraints,
      from: chainFirstOffset,
      to: chainLastEndOffset,
    );
    final double cacheExtent = calculateCacheOffset(
      constraints,
      from: chainFirstOffset,
      to: chainLastEndOffset,
    );
    if (chainLastIndex == count - 1 && chainLastEndOffset < scrollOffset) {
      childManager.setDidUnderflow(true);
    }

    double correction = 0;
    if (headEntry.index == 0 && headEntry.offset != 0) {
      correction = -headEntry.offset;
    }

    double scrollExtent;
    if (chainLastIndex == count - 1) {
      scrollExtent = chainLastEndOffset + correction;
    } else {
      double average;
      if (_extents.isNotEmpty) {
        double sum = 0;
        for (final double value in _extents.values) {
          sum += value;
        }
        average = sum / _extents.length;
      } else {
        average =
            (chainLastEndOffset - chainFirstOffset) /
            (chainLastIndex - chainFirstIndex + 1);
      }
      double tail = 0;
      for (int i = chainLastIndex + 1; i < count; i++) {
        tail += _extents[keys[i]] ?? average;
      }
      scrollExtent = chainLastEndOffset + correction + tail;
    }

    childManager.didFinishLayout();
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: scrollExtent,
      hasVisualOverflow: chainLastEndOffset > targetEnd || scrollOffset > 0,
      scrollOffsetCorrection: correction == 0 ? null : correction,
    );
    if (correction == 0) {
      _captureAnchor(
        keys,
        scrollOffset,
        chainFirstIndex,
        chainLastIndex,
        topMode,
      );
      _lastKeys = keys;
    }
  }

  void _anchoredPass(
    List<String> keys,
    double scrollOffset,
    double cacheStart,
    double targetEnd,
    BoxConstraints childConstraints,
    int anchorIndex,
    double anchorDy,
    GlobalKey? anchorSubKey,
    bool topMode,
  ) {
    final int count = keys.length;
    final RenderBox? obtained = _obtainChild(anchorIndex);
    if (obtained == null) {
      _degenerate(keys);
      return;
    }
    final RenderBox anchorChild = obtained;
    final double anchorExtent = _layoutChild(
      anchorChild,
      anchorIndex,
      keys,
      childConstraints,
    );
    double subNow = 0;
    double dy = anchorDy;
    if (!topMode && anchorSubKey != null) {
      final double? measured = _measureSub(anchorChild, anchorSubKey);
      if (measured != null) {
        subNow = measured;
      } else {
        dy = dy - _anchorSubOffset;
      }
    }
    final double anchorOffset = topMode ? 0 : scrollOffset + dy - subNow;
    _setChildOffset(anchorChild, anchorOffset);

    final List<_ChainEntry> chain = <_ChainEntry>[];

    final List<RenderBox> aboveChildren = <RenderBox>[];
    final List<int> aboveIndices = <int>[];
    final List<double> aboveExtents = <double>[];
    RenderBox? walker = firstChild;
    while (walker != null && indexOf(walker) < anchorIndex) {
      aboveChildren.add(walker);
      aboveIndices.add(indexOf(walker));
      walker = childAfter(walker);
    }
    for (int i = 0; i < aboveChildren.length; i++) {
      aboveExtents.add(
        _layoutChild(aboveChildren[i], aboveIndices[i], keys, childConstraints),
      );
    }
    double back = anchorOffset;
    final List<_ChainEntry> aboveEntries = <_ChainEntry>[];
    for (int i = aboveChildren.length - 1; i >= 0; i--) {
      back -= aboveExtents[i];
      _setChildOffset(aboveChildren[i], back);
      aboveEntries.add((
        index: aboveIndices[i],
        offset: back,
        extent: aboveExtents[i],
      ));
    }
    chain.addAll(aboveEntries.reversed);
    chain.add((index: anchorIndex, offset: anchorOffset, extent: anchorExtent));

    while (chain.first.offset >= cacheStart && chain.first.index > 0) {
      final RenderBox? created = insertAndLayoutLeadingChild(
        childConstraints,
        parentUsesSize: true,
      );
      if (created == null) {
        break;
      }
      final int index = chain.first.index - 1;
      final double extent = _recordExtent(created, index, keys);
      final double offset = chain.first.offset - extent;
      _setChildOffset(created, offset);
      chain.insert(0, (index: index, offset: offset, extent: extent));
    }

    double chainEnd = anchorOffset + anchorExtent;
    RenderBox child = anchorChild;
    while (chainEnd < targetEnd && chain.last.index < count - 1) {
      RenderBox? next = childAfter(child);
      if (next == null) {
        next = insertAndLayoutChild(
          childConstraints,
          after: lastChild,
          parentUsesSize: true,
        );
        if (next == null) {
          break;
        }
        final int index = chain.last.index + 1;
        final double extent = _recordExtent(next, index, keys);
        _setChildOffset(next, chainEnd);
        chain.add((index: index, offset: chainEnd, extent: extent));
        chainEnd += extent;
        child = next;
      } else {
        final int index = indexOf(next);
        final double extent = _layoutChild(next, index, keys, childConstraints);
        _setChildOffset(next, chainEnd);
        chain.add((index: index, offset: chainEnd, extent: extent));
        chainEnd += extent;
        child = next;
      }
    }

    _finishFromChain(keys, scrollOffset, cacheStart, targetEnd, chain, topMode);
  }

  void _basePass(
    List<String> keys,
    double scrollOffset,
    double cacheStart,
    double targetEnd,
    BoxConstraints childConstraints,
  ) {
    final int count = keys.length;
    RenderBox? first = firstChild;
    final bool baseValid =
        first != null &&
        (first.parentData as SliverMultiBoxAdaptorParentData).layoutOffset !=
            null;
    if (!baseValid) {
      if (first != null) {
        collectGarbage(_childCount(), 0);
      }
      if (!addInitialChild(index: 0, layoutOffset: 0)) {
        _degenerate(keys);
        return;
      }
      first = firstChild;
    }
    final RenderBox baseChild = first!;
    final int baseIndex = baseValid ? indexOf(baseChild) : 0;
    final double baseOffset = baseIndex == 0 ? 0 : _childOffset(baseChild);

    final List<_ChainEntry> chain = <_ChainEntry>[];
    double chainEnd = baseOffset;
    RenderBox? child = baseChild;
    while (child != null) {
      final int index = indexOf(child);
      final double extent = _layoutChild(child, index, keys, childConstraints);
      _setChildOffset(child, chainEnd);
      chain.add((index: index, offset: chainEnd, extent: extent));
      chainEnd += extent;
      if (chainEnd >= targetEnd) {
        break;
      }
      child = childAfter(child);
    }
    while (chainEnd < targetEnd && chain.last.index < count - 1) {
      final RenderBox? created = insertAndLayoutChild(
        childConstraints,
        after: lastChild,
        parentUsesSize: true,
      );
      if (created == null) {
        break;
      }
      final int index = chain.last.index + 1;
      final double extent = _recordExtent(created, index, keys);
      _setChildOffset(created, chainEnd);
      chain.add((index: index, offset: chainEnd, extent: extent));
      chainEnd += extent;
    }
    while (chain.first.offset >= cacheStart && chain.first.index > 0) {
      final RenderBox? created = insertAndLayoutLeadingChild(
        childConstraints,
        parentUsesSize: true,
      );
      if (created == null) {
        break;
      }
      final int index = chain.first.index - 1;
      final double extent = _recordExtent(created, index, keys);
      final double offset = chain.first.offset - extent;
      _setChildOffset(created, offset);
      chain.insert(0, (index: index, offset: offset, extent: extent));
    }

    _finishFromChain(keys, scrollOffset, cacheStart, targetEnd, chain, false);
  }

  @override
  void performLayout() {
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);
    final int count = _itemCount;
    final List<String> keys = List<String>.generate(count, _itemKeyAt);
    final double scrollOffset = constraints.scrollOffset;
    final double cacheStart = scrollOffset + constraints.cacheOrigin;
    final double targetEnd = cacheStart + constraints.remainingCacheExtent;
    final BoxConstraints childConstraints = constraints.asBoxConstraints();

    if (count == 0) {
      final int existing = _childCount();
      if (existing > 0) {
        collectGarbage(existing, 0);
      }
      _anchorKey = null;
      _anchorSubKey = null;
      _anchorDy = 0;
      _anchorSubOffset = 0;
      _anchorIndexHint = 0;
      _lastKeys = keys;
      childManager.didFinishLayout();
      geometry = const SliverGeometry(
        scrollExtent: 0,
        paintExtent: 0,
        maxPaintExtent: 0,
      );
      return;
    }

    final bool changed = _lastKeys == null || !_keysEqual(_lastKeys!, keys);
    final bool topMode = scrollOffset <= 2.0;

    if (topMode) {
      _anchoredPass(
        keys,
        scrollOffset,
        cacheStart,
        targetEnd,
        childConstraints,
        0,
        0,
        null,
        true,
      );
      return;
    }

    if (changed && _anchorKey != null) {
      int anchorIndex;
      GlobalKey? anchorSubKey = _anchorSubKey;
      double anchorDy = _anchorDy;
      if (_anchorIndexHint >= 0 &&
          _anchorIndexHint < count &&
          keys[_anchorIndexHint] == _anchorKey) {
        anchorIndex = _anchorIndexHint;
      } else {
        final int found = keys.indexOf(_anchorKey!);
        if (found >= 0) {
          anchorIndex = found;
        } else {
          anchorIndex = _anchorIndexHint.clamp(0, count - 1);
          anchorSubKey = null;
          anchorDy = math.max(0, _anchorDy - _anchorSubOffset);
        }
      }
      _anchoredPass(
        keys,
        scrollOffset,
        cacheStart,
        targetEnd,
        childConstraints,
        anchorIndex,
        anchorDy,
        anchorSubKey,
        false,
      );
      return;
    }

    _basePass(keys, scrollOffset, cacheStart, targetEnd, childConstraints);
  }
}
