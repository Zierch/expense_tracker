// Colours and shell pieces from the FigCraft "Expense Tracker — Web Desktop"
// design. Imported only by the wide-web branches; Android keeps its green
// theme and bottom navigation untouched.
//
// ponytail: one file of constants plus the sidebar. If the design ever grows
// beyond three screens, lift this into a proper web theme package.

import 'package:flutter/material.dart';

class WebDesktopStyle {
  static const Color background = Color(0xFF0B1220);
  static const Color sidebar = Color(0xFF0F1B2D);
  static const Color card = Color(0xFF16233A);
  static const Color inner = Color(0xFF131E31);
  static const Color activeNav = Color(0xFF163A34);
  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF7C8DA6);
  static const Color accent = Color(0xFF3B82F6);
  static const Color positive = Color(0xFF4ADE80);
  static const Color negative = Color(0xFFF87171);
  static const Color chip = Color(0xFF123A2C);

  static BoxDecoration cardDecoration({double radius = 20}) => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
      );
}

/// The 240px rail in the design: brand at the top, then three 60px-spaced
/// text items with the active one on a rounded green pill.
class WebSidebar extends StatelessWidget {
  const WebSidebar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const List<String> _labels = <String>['Home', 'Statistics', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: WebDesktopStyle.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(left: 32, top: 32, right: 16),
            child: Text(
              'Expense Tracker',
              style: TextStyle(
                color: WebDesktopStyle.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 62),
          for (int index = 0; index < _labels.length; index++)
            SizedBox(
              height: 60,
              child: _NavItem(
                label: _labels[index],
                active: index == selectedIndex,
                onTap: () => onSelected(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          // Full 60px row is tappable; only the centred 52px pill is painted.
          child: Container(
            height: 60,
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: Container(
                height: 52,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 16),
                decoration: active
                    ? BoxDecoration(
                        color: WebDesktopStyle.activeNav,
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color:
                        active ? WebDesktopStyle.positive : WebDesktopStyle.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
