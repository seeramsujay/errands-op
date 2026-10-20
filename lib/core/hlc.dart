import 'dart:math';

/// Hybrid Logical Clock (HLC) implementation for monotonic, causal timestamping.
/// Format: `<physical_ms>:<counter>:<node_id>`
class HlcTimestamp implements Comparable<HlcTimestamp> {
  final int physicalTime; // Milliseconds since epoch
  final int counter;
  final String nodeId;

  const HlcTimestamp({
    required this.physicalTime,
    required this.counter,
    required this.nodeId,
  });

  /// Parse from string representation
  factory HlcTimestamp.parse(String str) {
    final parts = str.split(':');
    if (parts.length < 3) {
      return HlcTimestamp(
        physicalTime: DateTime.now().millisecondsSinceEpoch,
        counter: 0,
        nodeId: 'unknown',
      );
    }
    return HlcTimestamp(
      physicalTime: int.tryParse(parts[0]) ?? 0,
      counter: int.tryParse(parts[1]) ?? 0,
      nodeId: parts.sublist(2).join(':'),
    );
  }

  @override
  String toString() => '$physicalTime:${counter.toString().padLeft(4, '0')}:$nodeId';

  @override
  int compareTo(HlcTimestamp other) {
    if (physicalTime != other.physicalTime) {
      return physicalTime.compareTo(other.physicalTime);
    }
    if (counter != other.counter) {
      return counter.compareTo(other.counter);
    }
    return nodeId.compareTo(other.nodeId);
  }

  bool isAfter(HlcTimestamp other) => compareTo(other) > 0;
  bool isBefore(HlcTimestamp other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HlcTimestamp &&
          runtimeType == other.runtimeType &&
          physicalTime == other.physicalTime &&
          counter == other.counter &&
          nodeId == other.nodeId;

  @override
  int get hashCode => physicalTime.hashCode ^ counter.hashCode ^ nodeId.hashCode;
}

/// Hybrid Logical Clock manager instance
class HybridLogicalClock {
  // Mutable so a persisted per-device id can be applied after startup.
  String nodeId;
  int _lastPhysicalTime = 0;
  int _counter = 0;

  HybridLogicalClock({String? nodeId})
      : nodeId = nodeId ?? 'node_${Random().nextInt(0xFFFFFF).toRadixString(16)}';

  /// Generate a new local HLC timestamp
  HlcTimestamp now() {
    final phys = DateTime.now().millisecondsSinceEpoch;
    if (phys > _lastPhysicalTime) {
      _lastPhysicalTime = phys;
      _counter = 0;
    } else {
      _counter++;
    }
    return HlcTimestamp(
      physicalTime: _lastPhysicalTime,
      counter: _counter,
      nodeId: nodeId,
    );
  }

  /// Update local clock based on an incoming remote timestamp (receive event)
  HlcTimestamp update(HlcTimestamp remote) {
    final phys = DateTime.now().millisecondsSinceEpoch;
    final maxPhys = max(phys, max(_lastPhysicalTime, remote.physicalTime));

    if (maxPhys == _lastPhysicalTime && maxPhys == remote.physicalTime) {
      _counter = max(_counter, remote.counter) + 1;
    } else if (maxPhys == _lastPhysicalTime) {
      _counter++;
    } else if (maxPhys == remote.physicalTime) {
      _counter = remote.counter + 1;
    } else {
      _counter = 0;
    }

    _lastPhysicalTime = maxPhys;
    return HlcTimestamp(
      physicalTime: _lastPhysicalTime,
      counter: _counter,
      nodeId: nodeId,
    );
  }
}
