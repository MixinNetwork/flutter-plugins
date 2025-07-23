import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

class WindowStyleSelector extends StatefulWidget {
  final Function(int style, int extendedStyle) onStyleChanged;
  final int initialStyle;
  final int initialExtendedStyle;

  const WindowStyleSelector({
    Key? key,
    required this.onStyleChanged,
    this.initialStyle = 0x00CF0000, // WS_OVERLAPPEDWINDOW | WS_VISIBLE
    this.initialExtendedStyle = 0x00000100, // WS_EX_WINDOWEDGE
  }) : super(key: key);

  @override
  _WindowStyleSelectorState createState() => _WindowStyleSelectorState();
}

class _WindowStyleSelectorState extends State<WindowStyleSelector> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _currentStyle;
  late int _currentExtendedStyle;
  List<String> _styleWarnings = [];

  // Regular window styles
  final List<StyleOption> _styles = [
    StyleOption(name: 'WS_OVERLAPPED', value: WindowsWindowStyle.WS_OVERLAPPED),
    StyleOption(name: 'WS_POPUP', value: WindowsWindowStyle.WS_POPUP),
    StyleOption(name: 'WS_CHILD', value: WindowsWindowStyle.WS_CHILD),
    StyleOption(name: 'WS_MINIMIZE', value: WindowsWindowStyle.WS_MINIMIZE),
    StyleOption(name: 'WS_VISIBLE', value: WindowsWindowStyle.WS_VISIBLE),
    StyleOption(name: 'WS_DISABLED', value: WindowsWindowStyle.WS_DISABLED),
    StyleOption(name: 'WS_CLIPSIBLINGS', value: WindowsWindowStyle.WS_CLIPSIBLINGS),
    StyleOption(name: 'WS_CLIPCHILDREN', value: WindowsWindowStyle.WS_CLIPCHILDREN),
    StyleOption(name: 'WS_MAXIMIZE', value: WindowsWindowStyle.WS_MAXIMIZE),
    StyleOption(name: 'WS_BORDER', value: WindowsWindowStyle.WS_BORDER),
    StyleOption(name: 'WS_DLGFRAME', value: WindowsWindowStyle.WS_DLGFRAME),
    StyleOption(name: 'WS_VSCROLL', value: WindowsWindowStyle.WS_VSCROLL),
    StyleOption(name: 'WS_HSCROLL', value: WindowsWindowStyle.WS_HSCROLL),
    StyleOption(name: 'WS_SYSMENU', value: WindowsWindowStyle.WS_SYSMENU),
    StyleOption(name: 'WS_THICKFRAME', value: WindowsWindowStyle.WS_THICKFRAME),
    StyleOption(name: 'WS_GROUP', value: WindowsWindowStyle.WS_GROUP),
    StyleOption(name: 'WS_TABSTOP', value: WindowsWindowStyle.WS_TABSTOP),
    StyleOption(name: 'WS_MINIMIZEBOX', value: WindowsWindowStyle.WS_MINIMIZEBOX),
    StyleOption(name: 'WS_MAXIMIZEBOX', value: WindowsWindowStyle.WS_MAXIMIZEBOX),
    StyleOption(name: 'WS_CAPTION', value: WindowsWindowStyle.WS_CAPTION)
  ];

  // Extended window styles
  final List<StyleOption> _extendedStyles = [
    StyleOption(name: 'WS_EX_DLGMODALFRAME', value: WindowsExtendedWindowStyle.WS_EX_DLGMODALFRAME),
    StyleOption(name: 'WS_EX_NOPARENTNOTIFY', value: WindowsExtendedWindowStyle.WS_EX_NOPARENTNOTIFY),
    StyleOption(name: 'WS_EX_TOPMOST', value: WindowsExtendedWindowStyle.WS_EX_TOPMOST),
    StyleOption(name: 'WS_EX_ACCEPTFILES', value: WindowsExtendedWindowStyle.WS_EX_ACCEPTFILES),
    StyleOption(name: 'WS_EX_TRANSPARENT', value: WindowsExtendedWindowStyle.WS_EX_TRANSPARENT),
    StyleOption(name: 'WS_EX_MDICHILD', value: WindowsExtendedWindowStyle.WS_EX_MDICHILD),
    StyleOption(name: 'WS_EX_TOOLWINDOW', value: WindowsExtendedWindowStyle.WS_EX_TOOLWINDOW),
    StyleOption(name: 'WS_EX_WINDOWEDGE', value: WindowsExtendedWindowStyle.WS_EX_WINDOWEDGE),
    StyleOption(name: 'WS_EX_CLIENTEDGE', value: WindowsExtendedWindowStyle.WS_EX_CLIENTEDGE),
    StyleOption(name: 'WS_EX_CONTEXTHELP', value: WindowsExtendedWindowStyle.WS_EX_CONTEXTHELP),
    StyleOption(name: 'WS_EX_RIGHT', value: WindowsExtendedWindowStyle.WS_EX_RIGHT),
    StyleOption(name: 'WS_EX_RTLREADING', value: WindowsExtendedWindowStyle.WS_EX_RTLREADING),
    StyleOption(name: 'WS_EX_LEFTSCROLLBAR', value: WindowsExtendedWindowStyle.WS_EX_LEFTSCROLLBAR),
    StyleOption(name: 'WS_EX_CONTROLPARENT', value: WindowsExtendedWindowStyle.WS_EX_CONTROLPARENT),
    StyleOption(name: 'WS_EX_STATICEDGE', value: WindowsExtendedWindowStyle.WS_EX_STATICEDGE),
    StyleOption(name: 'WS_EX_APPWINDOW', value: WindowsExtendedWindowStyle.WS_EX_APPWINDOW),
    StyleOption(name: 'WS_EX_LAYERED', value: WindowsExtendedWindowStyle.WS_EX_LAYERED),
    StyleOption(name: 'WS_EX_NOINHERITLAYOUT', value: WindowsExtendedWindowStyle.WS_EX_NOINHERITLAYOUT),
    StyleOption(name: 'WS_EX_LAYOUTRTL', value: WindowsExtendedWindowStyle.WS_EX_LAYOUTRTL),
    StyleOption(name: 'WS_EX_COMPOSITED', value: WindowsExtendedWindowStyle.WS_EX_COMPOSITED),
    StyleOption(name: 'WS_EX_NOACTIVATE', value: WindowsExtendedWindowStyle.WS_EX_NOACTIVATE),
  ];

  // Common style presets
  final Map<String, int> _stylePresets = {
    'WS_OVERLAPPEDWINDOW (Default)':
        0x00CF0000, // WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX
    'WS_POPUPWINDOW': -0x80880000, // WS_POPUP | WS_BORDER | WS_SYSMENU
    'WS_CHILDWINDOW': -0x40000000, // WS_CHILD
    'WS_CAPTION': 0x00C00000, // WS_BORDER | WS_DLGFRAME
    'No Border': 0x00080000, // WS_SYSMENU only
    'Fixed Size': 0x00C80000, // WS_CAPTION | WS_SYSMENU (no WS_THICKFRAME)
  };

  // Extended style presets
  final Map<String, int> _extendedStylePresets = {
    'WS_EX_OVERLAPPEDWINDOW': WindowsExtendedWindowStyle.WS_EX_OVERLAPPEDWINDOW,
    'WS_EX_PALETTEWINDOW': WindowsExtendedWindowStyle.WS_EX_PALETTEWINDOW,
    'WS_EX_TOOLWINDOW': WindowsExtendedWindowStyle.WS_EX_TOOLWINDOW,
    'WS_EX_APPWINDOW': WindowsExtendedWindowStyle.WS_EX_APPWINDOW,
    'WS_EX_TOPMOST': WindowsExtendedWindowStyle.WS_EX_TOPMOST,
    'No Extended Style': 0x00000000,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentStyle = widget.initialStyle;
    _currentExtendedStyle = widget.initialExtendedStyle;

    // Set initial checkbox states based on initial styles
    _updateCheckboxesFromStyle();
  }

  void _updateCheckboxesFromStyle() {
    // Update regular style checkboxes
    for (var style in _styles) {
      if (style.value == 0) {
        // Special case for WS_OVERLAPPED (0)
        style.isSelected = (_currentStyle & 0xF0000000) == 0;
      } else {
        style.isSelected = (_currentStyle & style.value) == style.value && style.value != 0;
      }
    }

    // Update extended style checkboxes
    for (var style in _extendedStyles) {
      style.isSelected = (_currentExtendedStyle & style.value) == style.value && style.value != 0;
    }
  }

  void _updateStyleFromCheckboxes() {
    int newStyle = 0;
    int newExtendedStyle = 0;

    // Calculate regular style
    for (var style in _styles) {
      if (style.isSelected && style.value != 0) {
        newStyle |= style.value;
      }
    }

    // Calculate extended style
    for (var style in _extendedStyles) {
      if (style.isSelected && style.value != 0) {
        newExtendedStyle |= style.value;
      }
    }

    // Check for incompatibilities
    List<String> warnings = _checkStyleIncompatibilities(newStyle, newExtendedStyle);

    setState(() {
      _currentStyle = newStyle;
      _currentExtendedStyle = newExtendedStyle;
      _styleWarnings = warnings;
    });

    widget.onStyleChanged(_currentStyle, _currentExtendedStyle);
  }

  List<String> _checkStyleIncompatibilities(int style, int extendedStyle) {
    List<String> warnings = [];

    // For debugging
    print('Current style: ${style.toRadixString(16)}');
    
    // Check base window type - using exact matches for the high bits
    bool hasPopup = style < 0 && (style & WindowsWindowStyle.WS_POPUP) == WindowsWindowStyle.WS_POPUP;
    bool hasChild = style < 0 && (style & WindowsWindowStyle.WS_CHILD) == WindowsWindowStyle.WS_CHILD;

    // Only warn if BOTH popup and child are selected
    if (hasPopup && hasChild) {
      warnings.add("WS_POPUP and WS_CHILD can't be used together");
    }

    // Check caption-related conflicts - positive values remain the same
    bool hasCaption = (style & WindowsWindowStyle.WS_CAPTION) == WindowsWindowStyle.WS_CAPTION;
    bool hasSysMenu = (style & WindowsWindowStyle.WS_SYSMENU) == WindowsWindowStyle.WS_SYSMENU;
    bool hasMinBox = (style & WindowsWindowStyle.WS_MINIMIZEBOX) == WindowsWindowStyle.WS_MINIMIZEBOX;
    bool hasMaxBox = (style & WindowsWindowStyle.WS_MAXIMIZEBOX) == WindowsWindowStyle.WS_MAXIMIZEBOX;

    // Only check child window restrictions if it's actually a child window
    if (hasChild) {
      if (hasCaption) {
        warnings.add("WS_CHILD windows shouldn't have WS_CAPTION");
      }
      if (hasSysMenu) {
        warnings.add("WS_CHILD windows shouldn't have WS_SYSMENU");
      }
      if ((extendedStyle & WindowsExtendedWindowStyle.WS_EX_APPWINDOW) == WindowsExtendedWindowStyle.WS_EX_APPWINDOW) {
        warnings.add("WS_CHILD can't be used with WS_EX_APPWINDOW");
      }
    }

    // Min/Max box requires caption
    if (!hasCaption) {
      if (hasMinBox) {
        warnings.add("WS_MINIMIZEBOX requires WS_CAPTION");
      }
      if (hasMaxBox) {
        warnings.add("WS_MAXIMIZEBOX requires WS_CAPTION");
      }
    }

    // System menu usually requires caption (except for popup windows)
    if (hasSysMenu && !hasCaption && !hasPopup) {
      warnings.add("WS_SYSMENU usually requires WS_CAPTION (except for popup windows)");
    }

    // Window state conflicts - negative values need exact comparison
    bool hasMinimize = (style & WindowsWindowStyle.WS_MINIMIZE) == WindowsWindowStyle.WS_MINIMIZE;
    bool hasMaximize = (style & WindowsWindowStyle.WS_MAXIMIZE) == WindowsWindowStyle.WS_MAXIMIZE;

    if (hasMinimize && hasMaximize) {
      warnings.add("Window cannot be both minimized and maximized");
    }

    // Extended style conflicts - all positive values, standard comparison works
    bool hasToolWindow = (extendedStyle & WindowsExtendedWindowStyle.WS_EX_TOOLWINDOW) == WindowsExtendedWindowStyle.WS_EX_TOOLWINDOW;
    bool hasAppWindow = (extendedStyle & WindowsExtendedWindowStyle.WS_EX_APPWINDOW) == WindowsExtendedWindowStyle.WS_EX_APPWINDOW;
    bool hasDialogFrame = (extendedStyle & WindowsExtendedWindowStyle.WS_EX_DLGMODALFRAME) == WindowsExtendedWindowStyle.WS_EX_DLGMODALFRAME;

    if (hasToolWindow && hasAppWindow) {
      warnings.add("WS_EX_TOOLWINDOW and WS_EX_APPWINDOW shouldn't be used together");
    }

    if (hasDialogFrame && hasPopup) {
      warnings.add("WS_EX_DLGMODALFRAME is typically used with overlapped windows, not popup windows");
    }

    // MDI-related checks
    bool hasMDIChild = (extendedStyle & WindowsExtendedWindowStyle.WS_EX_MDICHILD) == WindowsExtendedWindowStyle.WS_EX_MDICHILD;
    if (hasMDIChild && !hasChild) {
      warnings.add("WS_EX_MDICHILD requires WS_CHILD style");
    }

    return warnings;
  }

  void _selectStylePreset(int presetValue) {
    setState(() {
      _currentStyle = presetValue;
      _updateCheckboxesFromStyle();
    });
    widget.onStyleChanged(_currentStyle, _currentExtendedStyle);
  }

  void _selectExtendedStylePreset(int presetValue) {
    setState(() {
      _currentExtendedStyle = presetValue;
      _updateCheckboxesFromStyle();
    });
    widget.onStyleChanged(_currentStyle, _currentExtendedStyle);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 32, // Even smaller height
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                text: 'Window Styles',
                height: 28, // Smaller tab height
              ),
              Tab(
                text: 'Extended Styles',
                height: 28, // Smaller tab height
              ),
            ],
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).primaryColor,
            indicatorWeight: 2,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
              fontSize: 12, // Smaller font
              fontWeight: FontWeight.w500,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
            ),
            padding: EdgeInsets.zero,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildStylesTab(),
              _buildExtendedStylesTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStylesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact presets section
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const Text(
                'Presets:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: null,
                    isDense: true, // Makes the dropdown more compact
                    hint: const Text(
                      'Select a preset',
                      style: TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    onChanged: (String? newValue) {
                      if (newValue != null && _stylePresets.containsKey(newValue)) {
                        _selectStylePreset(_stylePresets[newValue]!);
                      }
                    },
                    items: _stylePresets.keys.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(
                          value,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Current style value
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            'Current Style: 0x${_currentStyle.toRadixString(16).padLeft(8, '0').toUpperCase()}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),

        // Style checkboxes
        Expanded(
          child: ListView.builder(
            itemCount: _styles.length,
            itemBuilder: (context, index) {
              final style = _styles[index];
              return CheckboxListTile(
                title: Text(
                  style.name,
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  '0x${style.value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                  style: const TextStyle(fontSize: 10),
                ),
                value: style.isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    style.isSelected = value ?? false;
                    _updateStyleFromCheckboxes();
                  });
                },
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),

        if (_styleWarnings.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              border: Border.all(color: Colors.amber.shade200),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Style Warnings:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 4),
                ...(_styleWarnings.map(
                  (warning) => Text(
                    '• $warning',
                    style: const TextStyle(fontSize: 11),
                  ),
                )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildExtendedStylesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact presets section
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const Text(
                'Presets:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: null,
                    isDense: true,
                    hint: const Text(
                      'Select a preset',
                      style: TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.arrow_drop_down, size: 16),
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    onChanged: (String? newValue) {
                      if (newValue != null && _extendedStylePresets.containsKey(newValue)) {
                        _selectExtendedStylePreset(_extendedStylePresets[newValue]!);
                      }
                    },
                    items: _extendedStylePresets.keys.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(
                          value,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Current extended style value
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            'Current Extended Style: 0x${_currentExtendedStyle.toRadixString(16).padLeft(8, '0').toUpperCase()}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),

        // Extended style checkboxes
        Expanded(
          child: ListView.builder(
            itemCount: _extendedStyles.length,
            itemBuilder: (context, index) {
              final style = _extendedStyles[index];
              return CheckboxListTile(
                title: Text(
                  style.name,
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  '0x${style.value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                  style: const TextStyle(fontSize: 10),
                ),
                value: style.isSelected,
                onChanged: (bool? value) {
                  setState(() {
                    style.isSelected = value ?? false;
                    _updateStyleFromCheckboxes();
                  });
                },
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

// Helper class to store style options
class StyleOption {
  final String name;
  final int value;
  bool isSelected;

  StyleOption({required this.name, required this.value, this.isSelected = false});
}

// Usage example
class WindowStyleExample extends StatefulWidget {
  const WindowStyleExample({Key? key}) : super(key: key);

  @override
  _WindowStyleExampleState createState() => _WindowStyleExampleState();
}

class _WindowStyleExampleState extends State<WindowStyleExample> {
  int _windowStyle = 0x00CF0000; // Default WS_OVERLAPPEDWINDOW
  int _extendedStyle = 0x00000100; // Default WS_EX_WINDOWEDGE

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Windows Style Selector'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: WindowStyleSelector(
                initialStyle: _windowStyle,
                initialExtendedStyle: _extendedStyle,
                onStyleChanged: (style, extendedStyle) {
                  setState(() {
                    _windowStyle = style;
                    _extendedStyle = extendedStyle;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Apply the window style
                print('Applying window style: 0x${_windowStyle.toRadixString(16).toUpperCase()}');
                print('Applying extended style: 0x${_extendedStyle.toRadixString(16).toUpperCase()}');
                // Here you would call your platform-specific code to apply the style
              },
              child: const Text('Apply Window Style'),
            ),
          ],
        ),
      ),
    );
  }
}
