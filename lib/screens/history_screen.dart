import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/models/train_record.dart';
import 'package:lbjconsole/services/merge_service.dart';

class HistoryScreen extends StatefulWidget {
  final Function(bool isEditing) onEditModeChanged;
  final Function() onSelectionChanged;

  const HistoryScreen({
    super.key,
    required this.onEditModeChanged,
    required this.onSelectionChanged,
  });

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  final List<Object> _displayItems = [];
  bool _isLoading = true;
  bool _isEditMode = false;
  final Set<String> _selectedRecords = {};
  final Map<String, bool> _expandedStates = {};
  final ScrollController _scrollController = ScrollController();
  bool _isAtTop = true;
  MergeSettings _mergeSettings = MergeSettings();

  int getSelectedCount() => _selectedRecords.length;
  Set<String> getSelectedRecordIds() => _selectedRecords;
  List<Object> getDisplayItems() => _displayItems;
  void clearSelection() => setState(() => _selectedRecords.clear());

  void setEditMode(bool isEditing) {
    setState(() {
      _isEditMode = isEditing;
      widget.onEditModeChanged(isEditing);
      if (!isEditing) {
        _selectedRecords.clear();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    loadRecords();
    _scrollController.addListener(() {
      if (_scrollController.position.atEdge) {
        if (_scrollController.position.pixels == 0) {
          if (!_isAtTop) setState(() => _isAtTop = true);
        }
      } else {
        if (_isAtTop) setState(() => _isAtTop = false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> loadRecords({bool scrollToTop = true}) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final allRecords = await DatabaseService.instance.getAllRecords();
      final settingsMap = await DatabaseService.instance.getAllSettings() ?? {};
      _mergeSettings = MergeSettings.fromMap(settingsMap);
      final items = MergeService.getMixedList(allRecords, _mergeSettings);

      if (mounted) {
        setState(() {
          _displayItems.clear();
          _displayItems.addAll(items);
          _isLoading = false;
        });
        if (scrollToTop && (_isAtTop) && _scrollController.hasClients) {
          _scrollController.animateTo(0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_displayItems.isEmpty) {
      return const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Text('暂无记录', style: TextStyle(color: Colors.white, fontSize: 18))
      ]));
    }
    return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        itemCount: _displayItems.length,
        itemBuilder: (context, index) {
          final item = _displayItems[index];
          if (item is MergedTrainRecord) {
            return _buildMergedRecordCard(item);
          } else if (item is TrainRecord) {
            return _buildRecordCard(item);
          }
          return const SizedBox.shrink();
        });
  }

  Widget _buildMergedRecordCard(MergedTrainRecord mergedRecord) {
    final bool isSelected =
        mergedRecord.records.any((r) => _selectedRecords.contains(r.uniqueId));
    final isExpanded = _expandedStates[mergedRecord.groupKey] ?? false;
    return Card(
        color: isSelected && _isEditMode
            ? const Color(0xFF2E2E2E)
            : const Color(0xFF1E1E1E),
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8.0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
                color: isSelected && _isEditMode
                    ? Colors.blue
                    : Colors.transparent,
                width: 2.0)),
        child: InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () {
              if (_isEditMode) {
                setState(() {
                  final allIdsInGroup =
                      mergedRecord.records.map((r) => r.uniqueId).toSet();
                  if (isSelected) {
                    _selectedRecords.removeAll(allIdsInGroup);
                  } else {
                    _selectedRecords.addAll(allIdsInGroup);
                  }
                  widget.onSelectionChanged();
                });
              } else {
                setState(
                    () => _expandedStates[mergedRecord.groupKey] = !isExpanded);
              }
            },
            onLongPress: () {
              if (!_isEditMode) setEditMode(true);
              setState(() {
                final allIdsInGroup =
                    mergedRecord.records.map((r) => r.uniqueId).toSet();
                _selectedRecords.addAll(allIdsInGroup);
                widget.onSelectionChanged();
              });
            },
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecordHeader(mergedRecord.latestRecord,
                          isMerged: true),
                      _buildPositionAndSpeed(mergedRecord.latestRecord),
                      _buildLocoInfo(mergedRecord.latestRecord),
                      if (isExpanded) _buildMergedExpandedContent(mergedRecord)
                    ]))));
  }

  Widget _buildMergedExpandedContent(MergedTrainRecord mergedRecord) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildExpandedMapForAll(mergedRecord.records),
        const Divider(color: Colors.white24, height: 24),
        ...mergedRecord.records.map((record) => _buildSubRecordItem(
            record, mergedRecord.latestRecord, _mergeSettings.groupBy)),
      ],
    );
  }

  Widget _buildSubRecordItem(
      TrainRecord record, TrainRecord latest, GroupBy groupBy) {
    String differingInfo = _getDifferingInfo(record, latest, groupBy);
    String locationInfo = _getLocationInfo(record);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                record.receivedTimestamp.toString().split('.')[0],
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (differingInfo.isNotEmpty)
                Text(
                  differingInfo,
                  style:
                      const TextStyle(color: Color(0xFF81D4FA), fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  locationInfo,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                record.speed.isNotEmpty ? "${record.speed} km/h" : "",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getDifferingInfo(
      TrainRecord record, TrainRecord latest, GroupBy groupBy) {
    final train = record.train.trim();
    final loco = record.loco.trim();
    final latestTrain = latest.train.trim();
    final latestLoco = latest.loco.trim();

    switch (groupBy) {
      case GroupBy.trainOnly:
        return loco != latestLoco && loco.isNotEmpty ? "机车: $loco" : "";
      case GroupBy.locoOnly:
        return train != latestTrain && train.isNotEmpty ? "车次: $train" : "";
      case GroupBy.trainOrLoco:
        if (train.isNotEmpty && train != latestTrain) return "车次: $train";
        if (loco.isNotEmpty && loco != latestLoco) return "机车: $loco";
        return "";
      case GroupBy.trainAndLoco:
        return "";
    }
  }

  String _getLocationInfo(TrainRecord record) {
    List<String> parts = [];
    if (record.route.isNotEmpty && record.route != "<NUL>")
      parts.add(record.route);
    if (record.direction != 0) parts.add(record.direction == 1 ? "下" : "上");
    if (record.position.isNotEmpty && record.position != "<NUL>")
      parts.add("${record.position}K");
    return parts.join(' ');
  }

  Widget _buildExpandedMapForAll(List<TrainRecord> records) {
    final positions = records
        .map((record) => _parsePosition(record.positionInfo))
        .whereType<LatLng>()
        .toList();
    if (positions.isEmpty) return const SizedBox.shrink();
    final bounds = LatLngBounds.fromPoints(positions);
    return Column(children: [
      const SizedBox(height: 8),
      Container(
          height: 220,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8), color: Colors.grey[900]),
          child: FlutterMap(
              options: MapOptions(
                  initialCenter: bounds.center,
                  initialZoom: 10,
                  minZoom: 5,
                  maxZoom: 18,
                  cameraConstraint: CameraConstraint.contain(bounds: bounds)),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'org.noxylva.lbjconsole'),
                MarkerLayer(
                    markers: positions
                        .map((pos) => Marker(
                            point: pos,
                            width: 40,
                            height: 40,
                            child: Container(
                                decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.8),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2)),
                                child: const Icon(Icons.train,
                                    color: Colors.white, size: 20))))
                        .toList())
              ]))
    ]);
  }

  Widget _buildRecordCard(TrainRecord record, {bool isSubCard = false}) {
    final isSelected = _selectedRecords.contains(record.uniqueId);
    final isExpanded =
        !isSubCard && (_expandedStates[record.uniqueId] ?? false);
    return Card(
        color: isSelected && _isEditMode
            ? const Color(0xFF2E2E2E)
            : const Color(0xFF1E1E1E),
        elevation: isSubCard ? 0 : 1,
        margin: EdgeInsets.only(bottom: isSubCard ? 4.0 : 8.0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
                color: isSelected && _isEditMode
                    ? Colors.blue
                    : Colors.transparent,
                width: 2.0)),
        child: InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () {
              if (_isEditMode) {
                setState(() {
                  if (isSelected) {
                    _selectedRecords.remove(record.uniqueId);
                  } else {
                    _selectedRecords.add(record.uniqueId);
                  }
                  widget.onSelectionChanged();
                });
              } else if (!isSubCard) {
                setState(() => _expandedStates[record.uniqueId] = !isExpanded);
              }
            },
            onLongPress: () {
              if (!_isEditMode) setEditMode(true);
              setState(() {
                _selectedRecords.add(record.uniqueId);
                widget.onSelectionChanged();
              });
            },
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecordHeader(record),
                      _buildPositionAndSpeed(record),
                      _buildLocoInfo(record),
                      if (isExpanded) _buildExpandedContent(record)
                    ]))));
  }

  Widget _buildRecordHeader(TrainRecord record, {bool isMerged = false}) {
    final trainType = record.trainType;
    final trainDisplay =
        record.fullTrainNumber.isEmpty ? "未知列车" : record.fullTrainNumber;
    String formattedLocoInfo = "";
    if (record.locoType.isNotEmpty && record.loco.isNotEmpty) {
      final shortLoco = record.loco.length > 5
          ? record.loco.substring(record.loco.length - 5)
          : record.loco;
      formattedLocoInfo = "${record.locoType}-$shortLoco";
    } else if (record.locoType.isNotEmpty) {
      formattedLocoInfo = record.locoType;
    } else if (record.loco.isNotEmpty) {
      formattedLocoInfo = record.loco;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text(
                (record.time == "<NUL>" || record.time.isEmpty)
                    ? record.receivedTimestamp.toString().split(".")[0]
                    : record.time.split("\n")[0],
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis)),
        if (trainType.isNotEmpty)
          Flexible(
              child: Text(trainType,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis))
      ]),
      const SizedBox(height: 2),
      Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                  Flexible(
                      child: Text(trainDisplay,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                          overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  if (record.direction == 1 || record.direction == 3)
                    Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2)),
                        child: Center(
                            child: Text(record.direction == 1 ? "下" : "上",
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black))))
                ])),
            if (formattedLocoInfo.isNotEmpty && formattedLocoInfo != "<NUL>")
              Text(formattedLocoInfo,
                  style: const TextStyle(fontSize: 14, color: Colors.white70))
          ]),
      const SizedBox(height: 2)
    ]);
  }

  Widget _buildLocoInfo(TrainRecord record) {
    final locoInfo = record.locoInfo;
    if (locoInfo == null || locoInfo.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      Text(locoInfo,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis)
    ]);
  }

  Widget _buildPositionAndSpeed(TrainRecord record) {
    final routeStr = record.route.trim();
    final position = record.position.trim();
    final speed = record.speed.trim();
    final isValidRoute = routeStr.isNotEmpty &&
        !routeStr.runes.every((r) => r == '*'.runes.first);
    final isValidPosition = position.isNotEmpty &&
        !position.runes
            .every((r) => r == '-'.runes.first || r == '.'.runes.first) &&
        position != "<NUL>";
    final isValidSpeed = speed.isNotEmpty &&
        !speed.runes
            .every((r) => r == '*'.runes.first || r == '-'.runes.first) &&
        speed != "NUL" &&
        speed != "<NUL>";
    if (!isValidRoute && !isValidPosition && !isValidSpeed)
      return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (isValidRoute || isValidPosition)
            Expanded(
                child: Row(children: [
              if (isValidRoute)
                Flexible(
                    child: Text(routeStr,
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white),
                        overflow: TextOverflow.ellipsis)),
              if (isValidRoute && isValidPosition) const SizedBox(width: 4),
              if (isValidPosition)
                Flexible(
                    child: Text("$position K",
                        style:
                            const TextStyle(fontSize: 16, color: Colors.white),
                        overflow: TextOverflow.ellipsis))
            ])),
          if (isValidSpeed)
            Text("$speed km/h",
                style: const TextStyle(fontSize: 16, color: Colors.white),
                textAlign: TextAlign.right)
        ]));
  }

  Widget _buildExpandedContent(TrainRecord record) {
    final position = _parsePosition(record.positionInfo);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (position != null)
        Column(children: [
          const SizedBox(height: 8),
          Container(
              height: 220,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[900]),
              child: FlutterMap(
                  options:
                      MapOptions(initialCenter: position, initialZoom: 15.0),
                  children: [
                    TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'org.noxylva.lbjconsole'),
                    MarkerLayer(markers: [
                      Marker(
                          point: position,
                          width: 40,
                          height: 40,
                          child: Container(
                              decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.white, width: 2)),
                              child: const Icon(Icons.train,
                                  color: Colors.white, size: 20)))
                    ])
                  ]))
        ])
    ]);
  }

  LatLng? _parsePosition(String? positionInfo) {
    if (positionInfo == null || positionInfo.isEmpty || positionInfo == '<NUL>')
      return null;
    try {
      final parts = positionInfo.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final lat = _parseDmsCoordinate(parts[0]);
        final lng = _parseDmsCoordinate(parts[1]);
        if (lat != null &&
            lng != null &&
            (lat.abs() > 0.001 || lng.abs() > 0.001)) {
          return LatLng(lat, lng);
        }
      }
    } catch (e) {}
    return null;
  }

  double? _parseDmsCoordinate(String dmsStr) {
    try {
      final degreeIndex = dmsStr.indexOf('°');
      if (degreeIndex == -1) return null;
      final degrees = double.tryParse(dmsStr.substring(0, degreeIndex));
      if (degrees == null) return null;
      final minuteIndex = dmsStr.indexOf('′');
      if (minuteIndex == -1) return degrees;
      final minutes =
          double.tryParse(dmsStr.substring(degreeIndex + 1, minuteIndex));
      if (minutes == null) return degrees;
      return degrees + (minutes / 60.0);
    } catch (e) {
      return null;
    }
  }
}
