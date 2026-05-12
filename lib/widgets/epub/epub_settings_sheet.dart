import 'package:flutter/material.dart';
import 'package:flureadium/flureadium.dart';

class EpubSettingsSheet extends StatefulWidget {
  final EPUBPreferences prefs;
  final Future<void> Function(EPUBPreferences) onChanged;

  const EpubSettingsSheet({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  @override
  State<EpubSettingsSheet> createState() => _EpubSettingsSheetState();
}

class _EpubSettingsSheetState extends State<EpubSettingsSheet> {
  late EPUBPreferences _current;

  // Theme presets
  static const _themes = [
    _ThemePreset('Light', Color(0xFFFFFFFF), Color(0xFF222222), 'Georgia'),
    _ThemePreset('Sepia', Color(0xFFF5E6D3), Color(0xFF5C4033), 'Palatino'),
    _ThemePreset('Dark', Color(0xFF1A1A1A), Color(0xFFE0E0E0), 'Helvetica'),
  ];

  static const _fonts = [
    'Georgia',
    'Palatino',
    'Helvetica',
    'Arial',
    'Verdana',
  ];

  @override
  void initState() {
    super.initState();
    _current = widget.prefs;
  }

  void _update(EPUBPreferences p) {
    setState(() => _current = p);
    widget.onChanged(p);
  }

  EPUBPreferences _withFontSize(int size) => EPUBPreferences(
    fontFamily: _current.fontFamily,
    fontSize: size,
    fontWeight: _current.fontWeight,
    verticalScroll: _current.verticalScroll,
    backgroundColor: _current.backgroundColor,
    textColor: _current.textColor,
  );

  EPUBPreferences _withFont(String family) => EPUBPreferences(
    fontFamily: family,
    fontSize: _current.fontSize,
    fontWeight: _current.fontWeight,
    verticalScroll: _current.verticalScroll,
    backgroundColor: _current.backgroundColor,
    textColor: _current.textColor,
  );

  EPUBPreferences _withScroll(bool v) => EPUBPreferences(
    fontFamily: _current.fontFamily,
    fontSize: _current.fontSize,
    fontWeight: _current.fontWeight,
    verticalScroll: v,
    backgroundColor: _current.backgroundColor,
    textColor: _current.textColor,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Text(
                'Reading Settings',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // Themes
              Text('Theme', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              Row(
                children: _themes.map((t) {
                  final active = _current.backgroundColor == t.bg;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => _update(
                          EPUBPreferences(
                            fontFamily: t.font,
                            fontSize: _current.fontSize,
                            fontWeight: _current.fontWeight,
                            verticalScroll: _current.verticalScroll,
                            backgroundColor: t.bg,
                            textColor: t.fg,
                          ),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 48,
                          decoration: BoxDecoration(
                            color: t.bg,
                            border: Border.all(
                              color: active ? cs.primary : Colors.grey.shade300,
                              width: active ? 2.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            t.label,
                            style: TextStyle(
                              color: t.fg,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Font size
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Font Size',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    '${_current.fontSize}%',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                min: 60,
                max: 200,
                divisions: 28,
                value: _current.fontSize.toDouble(),
                label: '${_current.fontSize}%',
                onChanged: (v) => _update(_withFontSize(v.round())),
              ),
              const SizedBox(height: 8),

              // Font family
              Text('Font', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _fonts.map((f) {
                    final active = _current.fontFamily == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f, style: TextStyle(fontFamily: f)),
                        selected: active,
                        onSelected: (_) => _update(_withFont(f)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Scroll mode
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Scroll Mode'),
                subtitle: const Text('Continuous vertical scrolling'),
                value: _current.verticalScroll ?? false,
                onChanged: (v) => _update(_withScroll(v)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreset {
  final String label;
  final Color bg;
  final Color fg;
  final String font;

  const _ThemePreset(this.label, this.bg, this.fg, this.font);
}
