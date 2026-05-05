import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/data/repositories/trip_repository.dart';

/// A text field with Google Places autocomplete suggestions.
///
/// When the user taps a suggestion, [onPlaceSelected] fires with the place
/// description, latitude and longitude.
///
/// [onTextChanged] fires with every keystroke so the parent can track the
/// raw text even when no suggestion is selected.
class LocationSearchField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final TripRepository tripRepository;
  final void Function(String description, double lat, double lng)
      onPlaceSelected;

  /// Called every time the text field value changes.
  final ValueChanged<String>? onTextChanged;

  const LocationSearchField({
    super.key,
    required this.label,
    required this.tripRepository,
    required this.onPlaceSelected,
    this.onTextChanged,
    this.initialValue,
  });

  @override
  State<LocationSearchField> createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<LocationSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, String>> _predictions = [];
  Timer? _debounce;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
  }

  void _onChanged(String value) {
    // Always notify the parent of the raw text.
    widget.onTextChanged?.call(value);
    setState(() {}); // refresh suffixIcon visibility

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (value.length < 2) {
        setState(() {
          _predictions = [];
          _showSuggestions = false;
        });
        return;
      }
      try {
        debugPrint('[LocationSearchField] Querying: "$value"');
        final results =
            await widget.tripRepository.placesAutocomplete(value);
        debugPrint('[LocationSearchField] Got ${results.length} results');
        if (mounted) {
          setState(() {
            _predictions = results;
            _showSuggestions = results.isNotEmpty;
          });
        }
      } catch (e) {
        debugPrint('[LocationSearchField] Autocomplete error: $e');
      }
    });
  }

  Future<void> _onPredictionTap(Map<String, String> prediction) async {
    final description = prediction['description'] ?? '';
    final placeId = prediction['place_id'] ?? '';

    _controller.text = description;
    setState(() => _showSuggestions = false);
    _focusNode.unfocus();

    // Also notify via onTextChanged so _from/_to stays in sync.
    widget.onTextChanged?.call(description);

    try {
      final coords = await widget.tripRepository.placeDetails(placeId);
      widget.onPlaceSelected(
        description,
        coords['lat']!,
        coords['lng']!,
      );
    } catch (e) {
      debugPrint('[LocationSearchField] Place details error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: ShaderMask(
              shaderCallback: (bounds) =>
                  AppTheme.primaryGradient.createShader(bounds),
              child: const Icon(Icons.location_on_outlined,
                  color: Colors.white),
            ),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        size: 18, color: AppTheme.textMuted),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _predictions = [];
                        _showSuggestions = false;
                      });
                      widget.onTextChanged?.call('');
                    },
                  )
                : null,
          ),
          onChanged: _onChanged,
        ),

        // ── Suggestions dropdown ────────────────────────────────────────
        if (_showSuggestions)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _predictions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppTheme.divider),
                itemBuilder: (context, i) {
                  final pred = _predictions[i];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _onPredictionTap(pred),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusSm),
                              ),
                              child: Icon(Icons.place_rounded,
                                  size: 16,
                                  color: AppTheme.primaryColor),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                pred['description'] ?? '',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
