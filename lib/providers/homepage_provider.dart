import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider managing homepage section ordering and visibility preferences.
class HomepageProvider extends ChangeNotifier {
  static const String _orderKey = 'homepage_section_order';
  static const String _hiddenKey = 'homepage_hidden_sections';

  List<String> _sectionOrder = [];
  Set<String> _hiddenSections = {};
  bool _isLoaded = false;

  HomepageProvider() {
    _loadFromPreferences();
  }

  List<String> get sectionOrder => List.unmodifiable(_sectionOrder);
  Set<String> get hiddenSections => Set.unmodifiable(_hiddenSections);
  bool get isLoaded => _isLoaded;

  bool isSectionVisible(String id) => !_hiddenSections.contains(id);

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList(_orderKey);
      final savedHidden = prefs.getStringList(_hiddenKey);

      if (savedOrder != null) {
        _sectionOrder = List<String>.from(savedOrder);
      }
      if (savedHidden != null) {
        _hiddenSections = Set<String>.from(savedHidden);
      }
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load homepage preferences: $e');
    }
  }

  /// Syncs newly discovered available sections with the custom ordering.
  void syncAvailableSections(List<String> availableIds) {
    if (availableIds.isEmpty) return;

    bool changed = false;

    if (_sectionOrder.isEmpty) {
      _sectionOrder = List<String>.from(availableIds);
      changed = true;
    } else {
      // Retain existing ordered items that are still available
      final updatedOrder = _sectionOrder.where((id) => availableIds.contains(id)).toList();

      // Append any newly available items not yet in sectionOrder
      for (final id in availableIds) {
        if (!updatedOrder.contains(id)) {
          updatedOrder.add(id);
        }
      }

      if (updatedOrder.length != _sectionOrder.length ||
          !listEquals(updatedOrder, _sectionOrder)) {
        _sectionOrder = updatedOrder;
        changed = true;
      }
    }

    if (changed) {
      _saveOrder();
      notifyListeners();
    }
  }

  Future<void> toggleSectionVisibility(String id) async {
    if (_hiddenSections.contains(id)) {
      _hiddenSections.remove(id);
    } else {
      _hiddenSections.add(id);
    }
    notifyListeners();
    await _saveHidden();
  }

  Future<void> reorderSections(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _sectionOrder.length) return;
    if (newIndex < 0 || newIndex > _sectionOrder.length) return;

    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }

    final item = _sectionOrder.removeAt(oldIndex);
    _sectionOrder.insert(targetIndex, item);
    notifyListeners();
    await _saveOrder();
  }

  Future<void> _saveOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderKey, _sectionOrder);
    } catch (e) {
      debugPrint('Failed to save homepage section order: $e');
    }
  }

  Future<void> _saveHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_hiddenKey, _hiddenSections.toList());
    } catch (e) {
      debugPrint('Failed to save homepage hidden sections: $e');
    }
  }
}
