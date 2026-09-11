import 'package:flutter/material.dart';

class OhMyBottomNavigationBar extends StatelessWidget {
  const OhMyBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const double height = 86;
  static const _blue = Color(0xFF3266CC);

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _destinations = <_OhMyDestination>[
    _OhMyDestination('Home', 'homeOff.png', 'homeOn.png'),
    _OhMyDestination('AI Chat', 'aiBotOff.png', 'aiBotOn.png'),
    _OhMyDestination('Start Trip', 'tripOff.png', 'tripOn.png'),
    _OhMyDestination(
      'Community',
      'commDiscoveryOff.png',
      'commDiscoveryOn.png',
    ),
    _OhMyDestination('Profile', 'userProfileOff.png', 'userProfileOn.png'),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Main navigation',
      child: SizedBox(
        height: height,
        child: Material(
          color: Colors.white,
          elevation: 14,
          shadowColor: Colors.black26,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(_destinations.length, (index) {
              final destination = _destinations[index];
              final selected = selectedIndex == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: destination.label,
                  child: InkResponse(
                    onTap: () => onSelected(index),
                    radius: 38,
                    containedInkWell: false,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          top: selected ? -18 : 12,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            width: selected ? 58 : 34,
                            height: selected ? 58 : 34,
                            padding: EdgeInsets.all(selected ? 6 : 3),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: selected
                                  ? Border.all(color: _blue, width: 3)
                                  : null,
                              boxShadow: selected
                                  ? const [
                                      BoxShadow(
                                        color: Color(0x333266CC),
                                        blurRadius: 12,
                                        offset: Offset(0, 5),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Image.asset(
                                'assets/images/navigation/${selected ? destination.onAsset : destination.offAsset}',
                                key: ValueKey(selected),
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 2,
                          right: 2,
                          bottom: 20,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected ? _blue : const Color(0xFF929AA8),
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _OhMyDestination {
  const _OhMyDestination(this.label, this.offAsset, this.onAsset);

  final String label;
  final String offAsset;
  final String onAsset;
}
