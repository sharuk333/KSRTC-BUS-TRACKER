import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';
import 'package:ksrtc_smarttrack/data/repositories/bus_repository.dart';

// ── Repository singleton ─────────────────────────────────────────────────
final busRepositoryProvider = Provider<BusRepository>((ref) {
  return BusRepository();
});

// ── Buses owned by the current conductor (real-time) ────────────────────
final conductorBusesProvider =
    StreamProvider.family<List<BusModel>, String>((ref, conductorId) {
  return ref.watch(busRepositoryProvider).busesStream(conductorId);
});
