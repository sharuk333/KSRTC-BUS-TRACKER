import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ksrtc_smarttrack/core/constants/app_constants.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';
import 'package:ksrtc_smarttrack/presentation/widgets/location_search_field.dart';
import 'package:ksrtc_smarttrack/providers/auth_provider.dart';
import 'package:ksrtc_smarttrack/providers/bus_provider.dart';
import 'package:ksrtc_smarttrack/providers/trip_provider.dart';

/// Screen for adding a new bus or editing an existing one.
///
/// When [existingBus] is null a new bus is created.
/// When [existingBus] is provided, the form is pre-filled and an update is
/// performed on save.
class AddEditBusScreen extends ConsumerStatefulWidget {
  final BusModel? existingBus;

  const AddEditBusScreen({super.key, this.existingBus});

  @override
  ConsumerState<AddEditBusScreen> createState() => _AddEditBusScreenState();
}

class _AddEditBusScreenState extends ConsumerState<AddEditBusScreen> {
  final _formKey = GlobalKey<FormState>();
  final _busNumberCtrl = TextEditingController();

  String _busType = AppConstants.busTypes.first;
  String _shift = AppConstants.shifts.first;

  String? _fromPlace;
  double? _fromLat;
  double? _fromLng;

  String? _toPlace;
  double? _toLat;
  double? _toLng;

  bool _loading = false;

  bool get _isEditing => widget.existingBus != null;

  @override
  void initState() {
    super.initState();
    final bus = widget.existingBus;
    if (bus != null) {
      _busNumberCtrl.text = bus.busNumber;
      _busType = bus.busType;
      _shift = bus.shift;
      _fromPlace = bus.fromPlace;
      _fromLat = bus.fromLat;
      _fromLng = bus.fromLng;
      _toPlace = bus.toPlace;
      _toLat = bus.toLat;
      _toLng = bus.toLng;
    }
  }

  @override
  void dispose() {
    _busNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fromPlace == null || _fromLat == null || _fromLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a From location.')),
      );
      return;
    }
    if (_toPlace == null || _toLat == null || _toLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a To location.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) throw 'Not authenticated.';

      final repo = ref.read(busRepositoryProvider);
      final busNumber = _busNumberCtrl.text.trim();

      // ── Duplicate bus-number guard ───────────────────────────────────────
      // On add: reject if any document already has this bus number.
      // On edit: reject if any OTHER document already has this bus number.
      final duplicate = await repo.busNumberExists(
        busNumber,
        excludeBusId: _isEditing ? widget.existingBus!.busId : null,
      );
      if (duplicate) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Bus number "$busNumber" already exists. '
                'Each bus must have a unique number.',
              ),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }

      if (_isEditing) {
        final updated = widget.existingBus!.copyWith(
          busNumber: _busNumberCtrl.text.trim(),
          busType: _busType,
          shift: _shift,
          fromPlace: _fromPlace,
          fromLat: _fromLat,
          fromLng: _fromLng,
          toPlace: _toPlace,
          toLat: _toLat,
          toLng: _toLng,
        );
        await repo.updateBus(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bus updated successfully.')),
          );
          Navigator.of(context).pop();
        }
      } else {
        final newBus = BusModel(
          busId: '',
          conductorId: user.uid,
          busNumber: _busNumberCtrl.text.trim(),
          busType: _busType,
          shift: _shift,
          fromPlace: _fromPlace!,
          fromLat: _fromLat!,
          fromLng: _fromLng!,
          toPlace: _toPlace!,
          toLat: _toLat!,
          toLng: _toLng!,
          createdAt: DateTime.now(),
        );
        await repo.addBus(newBus);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bus added successfully.')),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripRepo = ref.read(tripRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Bus' : 'Add Bus',
          style: const TextStyle(color: AppTheme.primaryColor),
        ),
        foregroundColor: AppTheme.primaryColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Bus Number ────────────────────────────────────────
                TextFormField(
                  controller: _busNumberCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Bus Number',
                    prefixIcon: Icon(Icons.directions_bus),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                  // ── Bus Type ──────────────────────────────────────────
                  DropdownButtonFormField<String>(
                    initialValue: _busType,
                  decoration: const InputDecoration(
                    labelText: 'Bus Type',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: AppConstants.busTypes
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _busType = v!),
                ),
                const SizedBox(height: 16),

                  // ── Shift ─────────────────────────────────────────────
                  DropdownButtonFormField<String>(
                    initialValue: _shift,
                  decoration: const InputDecoration(
                    labelText: 'Shift',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  items: AppConstants.shifts
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _shift = v!),
                ),
                const SizedBox(height: 24),

                // ── From ──────────────────────────────────────────────
                Text(
                  'Route Endpoints',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                LocationSearchField(
                  label: 'From (Origin)',
                  tripRepository: tripRepo,
                  initialValue: _fromPlace,
                  onPlaceSelected: (desc, lat, lng) {
                    setState(() {
                      _fromPlace = desc;
                      _fromLat = lat;
                      _fromLng = lng;
                    });
                  },
                ),
                if (_fromPlace != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      '✓ $_fromPlace',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.primaryColor),
                    ),
                  ),
                const SizedBox(height: 16),

                LocationSearchField(
                  label: 'To (Destination)',
                  tripRepository: tripRepo,
                  initialValue: _toPlace,
                  onPlaceSelected: (desc, lat, lng) {
                    setState(() {
                      _toPlace = desc;
                      _toLat = lat;
                      _toLng = lng;
                    });
                  },
                ),
                if (_toPlace != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      '✓ $_toPlace',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.primaryColor),
                    ),
                  ),
                const SizedBox(height: 32),

                // ── Save ──────────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: _loading ? null : _save,
                  icon: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isEditing ? 'Update Bus' : 'Add Bus'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
