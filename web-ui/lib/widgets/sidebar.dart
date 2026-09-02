import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Navigation item definition for the sidebar.
class SidebarItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int? badgeCount;
  final bool showBadge;

  const SidebarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount,
    this.showBadge = false,
  });
}

/// Professional sidebar widget for the Gubernator dashboard.
/// Supports collapse/expand, badges, active indicator, and theme toggle.
class GubernatorSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final String version;
  final bool updateAvailable;
  final String latestVersion;
  final VoidCallback? onVersionCheckPressed;
  final VoidCallback? onUpdatePressed;
  final VoidCallback onSettingsPressed;
  final List<SidebarItem> items;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final bool monitorRunning;

  const GubernatorSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.isDark,
    required this.onThemeChanged,
    required this.version,
    this.updateAvailable = false,
    this.latestVersion = '',
    this.onVersionCheckPressed,
    this.onUpdatePressed,
    required this.onSettingsPressed,
    required this.items,
    required this.isCollapsed,
    required this.onToggleCollapse,
    this.monitorRunning = false,
  });

  @override
  State<GubernatorSidebar> createState() => _GubernatorSidebarState();
}

class _GubernatorSidebarState extends State<GubernatorSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _widthAnimation;

  static const double _defaultExpandedWidth = 280.0;
  static const double _updateExpandedWidth = 315.0;
  static const double _collapsedWidth = 72.0;

  double get _currentExpandedWidth =>
      widget.updateAvailable ? _updateExpandedWidth : _defaultExpandedWidth;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _widthAnimation = Tween<double>(
      begin: widget.isCollapsed ? _collapsedWidth : _currentExpandedWidth,
      end: widget.isCollapsed ? _collapsedWidth : _currentExpandedWidth,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(GubernatorSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCollapsed != widget.isCollapsed ||
        oldWidget.updateAvailable != widget.updateAvailable) {
      _widthAnimation = Tween<double>(
        begin: _widthAnimation.value,
        end: widget.isCollapsed ? _collapsedWidth : _currentExpandedWidth,
      ).animate(CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOut,
      ));
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? sidebarDarkBg : sidebarLightBg;
    final borderColor = isDark ? sidebarDarkBorder : sidebarLightBorder;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : const Color(0xFF94A3B8);

    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, child) {
        final width = _widthAnimation.value;
        final isExpanded = width > _collapsedWidth + 20;

        return Container(
          width: width,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              right: BorderSide(color: borderColor, width: 1),
            ),
          ),
          child: Column(
            children: [
              // ─── Logo Header ────────────────────────────────
              _buildLogoHeader(theme, isExpanded, textColor, mutedColor),

              const SizedBox(height: 8),

              // ─── Navigation Items ────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  children: [
                    for (int i = 0; i < widget.items.length; i++) ...[
                      // Section divider before Monitoring (index 9)
                      if (i == 9)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Divider(
                            height: 1,
                            color: borderColor,
                          ),
                        ),
                      _buildNavItem(
                        index: i,
                        item: widget.items[i],
                        isExpanded: isExpanded,
                        theme: theme,
                        textColor: textColor,
                        mutedColor: mutedColor,
                      ),
                    ],
                  ],
                ),
              ),

              // ─── Bottom Section ──────────────────────────────
              _buildBottomSection(theme, isExpanded, textColor, mutedColor, borderColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogoHeader(ThemeData theme, bool isExpanded, Color textColor, Color mutedColor) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(
        isExpanded ? 20 : 16,
        20,
        isExpanded ? 12 : 16,
        12,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? sidebarDarkBorder : sidebarLightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo icon with dark slate background and orange glow/border
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFF97316).withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF97316).withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Image.network(
                '/gubernator-icon.png',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.hub,
                  color: Color(0xFFF97316),
                  size: 24,
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gubernator',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (widget.updateAvailable && widget.onUpdatePressed != null)
                    InkWell(
                      onTap: widget.onUpdatePressed,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // First portion in Orange
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF97316).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'MANAGER ${widget.version}',
                                style: const TextStyle(
                                  color: Color(0xFFF97316),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3),
                              child: Text(
                                '→',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Second portion in Red
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'MANAGER ${widget.latestVersion}',
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.rocket_launch,
                              size: 11,
                              color: Color(0xFFEF4444),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        Tooltip(
                          message: 'Click to scan GitHub for new releases',
                          child: InkWell(
                            onTap: widget.onVersionCheckPressed,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: sidebarActiveIndicator.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: sidebarActiveIndicator.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'MANAGER ${widget.version}',
                                    style: const TextStyle(
                                      color: sidebarActiveIndicator,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.search, size: 10, color: sidebarActiveIndicator),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required SidebarItem item,
    required bool isExpanded,
    required ThemeData theme,
    required Color textColor,
    required Color mutedColor,
  }) {
    final isSelected = widget.selectedIndex == index;
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg = isDark
        ? sidebarActiveIndicator.withValues(alpha: 0.12)
        : sidebarActiveIndicator.withValues(alpha: 0.08);
    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: hoverBg,
          onTap: () => widget.onDestinationSelected(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 12 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                // Active indicator bar
                if (isSelected)
                  Container(
                    width: 3,
                    height: 20,
                    margin: EdgeInsets.only(right: isExpanded ? 10 : 0),
                    decoration: BoxDecoration(
                      color: sidebarActiveIndicator,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                else
                  SizedBox(width: isExpanded ? 13 : 0),

                // Icon with badge
                _buildIconWithBadge(
                  icon: isSelected ? item.activeIcon : item.icon,
                  isSelected: isSelected,
                  badgeCount: item.badgeCount,
                  showBadge: item.showBadge,
                  theme: theme,
                  textColor: textColor,
                  mutedColor: mutedColor,
                ),

                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: isSelected ? textColor : mutedColor,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Badge count text (shown in expanded mode)
                  if (item.showBadge && item.badgeCount != null && item.badgeCount! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${item.badgeCount}',
                        style: TextStyle(
                          color: isSelected
                              ? sidebarActiveIndicator
                              : mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconWithBadge({
    required IconData icon,
    required bool isSelected,
    int? badgeCount,
    bool showBadge = false,
    required ThemeData theme,
    required Color textColor,
    required Color mutedColor,
  }) {
    final iconWidget = Icon(
      icon,
      size: 22,
      color: isSelected ? sidebarActiveIndicator : mutedColor,
    );

    if (!showBadge || badgeCount == null || badgeCount <= 0 || !widget.isCollapsed) {
      return iconWidget;
    }

    // In collapsed mode, show badge on icon
    return Badge(
      label: Text(
        badgeCount > 99 ? '99+' : '$badgeCount',
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
      ),
      backgroundColor: sidebarActiveIndicator,
      child: iconWidget,
    );
  }

  Widget _buildBottomSection(
    ThemeData theme,
    bool isExpanded,
    Color textColor,
    Color mutedColor,
    Color borderColor,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: borderColor),
        ),
      ),
      child: Column(
        children: [
          // Collapse/Expand button
          _buildBottomButton(
            icon: widget.isCollapsed
                ? Icons.chevron_right
                : Icons.chevron_left,
            label: widget.isCollapsed ? 'Expand' : 'Collapse',
            isExpanded: isExpanded,
            textColor: mutedColor,
            onTap: widget.onToggleCollapse,
          ),

          const SizedBox(height: 4),

          // Theme toggle
          _buildBottomButton(
            icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            label: isDark ? 'Light Mode' : 'Dark Mode',
            isExpanded: isExpanded,
            textColor: mutedColor,
            onTap: () => widget.onThemeChanged(!widget.isDark),
          ),

          const SizedBox(height: 4),

          // Settings
          _buildBottomButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isExpanded: isExpanded,
            textColor: mutedColor,
            onTap: widget.onSettingsPressed,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required bool isExpanded,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isExpanded ? 12 : 0,
            vertical: 8,
          ),
          child: Row(
            mainAxisAlignment: isExpanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: textColor),
              if (isExpanded) ...[
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
