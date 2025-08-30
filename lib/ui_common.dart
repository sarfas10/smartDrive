import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Brand
/// ─────────────────────────────────────────────────────────────────────────────
const Color kBrand = Color(0xFF4c63d2);

/// ─────────────────────────────────────────────────────────────────────────────
/// % Helpers (use screen width/height/shortest side as percentage units)
/// Usage: context.wp(30) => 30% of width, context.hp(10) => 10% of height,
///        context.sp(2)  => 2% of shortest side (good for fonts / radii)
/// ─────────────────────────────────────────────────────────────────────────────
extension Pct on BuildContext {
  Size get _sz => MediaQuery.of(this).size;
  double wp(double percent) => _sz.width * percent / 100.0;
  double hp(double percent) => _sz.height * percent / 100.0;
  double sp(double percent) => (_sz.shortestSide) * percent / 100.0;
}
double _clamp(double v, double min, double max) => v.clamp(min, max).toDouble();

/// ─────────────────────────────────────────────────────────────────────────────
/// Background & Glass
/// ─────────────────────────────────────────────────────────────────────────────
class BgGradient extends StatelessWidget {
  const BgGradient({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        ),
      ),
    );
  }
}

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  const Glass({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) {
    // Radius ~1.6% of shortest side; clamp to keep aesthetics
    final radius = _clamp(context.sp(1.6), 10, 18);
    final pad = padding ?? EdgeInsets.all(_clamp(context.sp(1.2), 8, 18));

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AnimatedContainer(
        clipBehavior: Clip.antiAlias,
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: const Color(0xF5FFFFFF),
          border: Border.all(color: Colors.white.withOpacity(0.20)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: _clamp(context.sp(2.0), 8, 22))],
        ),
        child: Padding(padding: pad, child: child),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Header Bar
/// ─────────────────────────────────────────────────────────────────────────────
class HeaderBar extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const HeaderBar({super.key, required this.title, this.trailing});
  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.all(_clamp(context.wp(2.5), 10, 22));
    final titleSize = _clamp(context.sp(2.6), 18, 28);
    final chip = _clamp(context.wp(6.5), 28, 44); // avatar diameter
    final nameSize = _clamp(context.sp(1.8), 11, 15);

    return Padding(
      padding: pad,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w700, color: Colors.black87),
            ),
          ),
          SizedBox(width: _clamp(context.wp(2), 8, 14)),
          trailing ??
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: chip, height: chip, alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF4c63d2), Color(0xFF764ba2)]),
                    ),
                    child: Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: _clamp(context.sp(1.8), 11, 16))),
                  ),
                  SizedBox(width: _clamp(context.wp(1.8), 6, 12)),
                  Text('Admin User', style: TextStyle(fontWeight: FontWeight.w600, fontSize: nameSize)),
                ],
              ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Section & Table Headers
/// ─────────────────────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});
  @override
  Widget build(BuildContext context) {
    final fs = _clamp(context.sp(2.0), 13, 18);
    return Container(
      padding: EdgeInsets.fromLTRB(context.wp(3), context.hp(1.2), context.wp(3), context.hp(0.8)),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: fs),
            ),
          ),
        ],
      ),
    );
  }
}

class TableHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const TableHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final fs = _clamp(context.sp(2.1), 14, 19);
    final trailingFs = _clamp(context.sp(1.8), 12, 16);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.wp(3),
        context.hp(1.2),
        context.wp(3),
        context.hp(0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: fs,
                color: Colors.black87, // title always black87
              ),
            ),
          ),
          if (trailing != null)
            DefaultTextStyle.merge(
              style: TextStyle(fontSize: trailingFs, color: Colors.black87),
              child: IconTheme.merge(
                data: const IconThemeData(color: Colors.black87),
                child: trailing!,
              ),
            ),
        ],
      ),
    );
  }
}


/// ─────────────────────────────────────────────────────────────────────────────
/// Data Table (horizontal scroll on small screens)
/// ─────────────────────────────────────────────────────────────────────────────
class DataTableWrap extends StatelessWidget {
  final List<String> columns;
  final List<List<Widget>> rows;
  const DataTableWrap({super.key, required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    final headingFs = _clamp(context.sp(1.8), 12, 15);
    final cellFs = _clamp(context.sp(1.8), 12, 15);
    final colSpacing = _clamp(context.wp(3), 16, 36);
    final rowMinH = _clamp(context.hp(5), 36, 60);
    final rowMaxH = _clamp(context.hp(7), 52, 72);
    final cellPadV = _clamp(context.hp(0.9), 4, 10);

    final table = DataTable(
      headingRowColor: const WidgetStatePropertyAll(Color(0x1A4C63D2)),
      columnSpacing: colSpacing,
      dataRowMinHeight: rowMinH,
      dataRowMaxHeight: rowMaxH,
      columns: columns
          .map(
            (c) => DataColumn(
              label: Text(
                c,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kBrand, // brand color for headers
                  fontSize: headingFs,
                ),
              ),
            ),
          )
          .toList(),
      rows: rows
          .map(
            (cells) => DataRow(
              cells: cells
                  .map(
                    (w) => DataCell(
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: _clamp(context.wp(8), 40, 120),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: cellPadV),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(
                              fontSize: cellFs,
                              color: Colors.black54,
                            ),
                            child: IconTheme.merge(
                              data: const IconThemeData(color: Colors.black87),
                              child: w,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: table,
    );
  }
}


/// ─────────────────────────────────────────────────────────────────────────────
/// Cards & Stats (percentage-based sizing; no overflow)
/// ─────────────────────────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final String? title;
  final Widget child;
  const AppCard({super.key, this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    final titleFs = _clamp(context.sp(2.2), 15, 20);
    final gap = _clamp(context.hp(1), 6, 10);
    return Glass(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: TextStyle(fontSize: titleFs, fontWeight: FontWeight.w700, color: Colors.black87)),
              SizedBox(height: gap),
              const Divider(height: 1),
              SizedBox(height: gap),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Grid where tile width/height are driven by screen %.
/// - targetTileWidthPct: desired width per card as % of screen width
/// - tileHeightPct:      desired height per card as % of screen height
class StatsGrid extends StatelessWidget {
  final List<Widget> cards;
  final double targetTileWidthPct;
  final double tileHeightPct;
  final double mainAxisSpacingPct;   // % of width
  final double crossAxisSpacingPct;  // % of width
  final int maxCols;

  const StatsGrid({
    super.key,
    required this.cards,
    this.targetTileWidthPct = 30, // ~3 columns on desktop (30% each)
    this.tileHeightPct = 11,      // ~11% of screen height
    this.mainAxisSpacingPct = 1.5,
    this.crossAxisSpacingPct = 1.5,
    this.maxCols = 4,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        final targetTileW = context.wp(targetTileWidthPct);
        int cols = (w / targetTileW).floor();
        cols = cols.clamp(1, maxCols);

        final gapX = context.wp(crossAxisSpacingPct);
        final totalGap = gapX * (cols - 1);
        final tileW = (w - totalGap) / cols;

        final tileH = context.hp(tileHeightPct);
        final childAspectRatio = tileW / tileH;

        return GridView.builder(
          itemCount: cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gapX,
            mainAxisSpacing: context.wp(mainAxisSpacingPct),
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (_, i) => cards[i],
        );
      },
    );
  }
}

class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color tint;
  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.tint = kBrand,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = _clamp(context.wp(6), 30, 46);
    final iconSize = _clamp(context.sp(2.2), 16, 22);
    final vFs = _clamp(context.sp(2.8), 22, 32);
    final lFs = _clamp(context.sp(1.8), 12, 15);
    final hGap = _clamp(context.wp(2), 8, 14);
    final vPadGuard = _clamp(context.hp(0.5), 2, 6);

    return AppCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: vPadGuard),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: iconBox, height: iconBox, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(_clamp(context.sp(1.2), 8, 12)),
                  border: Border.all(color: tint.withOpacity(0.20), width: 0.8),
                ),
                child: Icon(icon, color: tint, size: iconSize),
              ),
              SizedBox(width: hGap),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(color: tint, fontSize: vFs, fontWeight: FontWeight.w800, height: 1.05),
                    ),
                  ),
                  SizedBox(height: _clamp(context.hp(0.6), 4, 8)),
                  Text(
                    label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.black54, fontSize: lFs, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Badges & Pills
/// ─────────────────────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String text;
  final String? type; // 'pending' | 'approved' | 'rejected' | 'active'
  const StatusBadge({super.key, required this.text, this.type});
  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (type) {
      case 'pending':  bg = const Color(0xFFFFF3CD); fg = const Color(0xFF856404); break;
      case 'approved':
      case 'active':   bg = const Color(0xFFD4EDDA); fg = const Color(0xFF155724); break;
      case 'rejected': bg = const Color(0xFFF8D7DA); fg = const Color(0xFF721C24); break;
      default:         bg = const Color(0xFFE9ECEF); fg = const Color(0xFF495057);
    }
    final padH = _clamp(context.wp(2.2), 8, 12);
    final padV = _clamp(context.hp(0.5), 3, 6);
    final fs = _clamp(context.sp(1.6), 10, 12);
    final radius = _clamp(context.sp(1.2), 10, 14);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Text(text.toUpperCase(), style: TextStyle(color: fg, fontSize: fs, fontWeight: FontWeight.w700)),
    );
  }
}

class RoleBadge extends StatelessWidget {
  final String role; // student | instructor | admin
  const RoleBadge({super.key, required this.role});
  @override
  Widget build(BuildContext context) {
    final isInstructor = role == 'instructor';
    final isAdmin = role == 'admin';
    Color bg, fg;
    if (isAdmin)      { bg = const Color(0xFFEDE7F6); fg = const Color(0xFF5E35B1); }
    else if (isInstructor) { bg = const Color(0xFFE3F2FD); fg = const Color(0xFF1565C0); }
    else              { bg = const Color(0xFFFFF8E1); fg = const Color(0xFFCC6E00); }

    final padH = _clamp(context.wp(2.2), 8, 12);
    final padV = _clamp(context.hp(0.5), 3, 6);
    final fs = _clamp(context.sp(1.6), 10, 12);
    final radius = _clamp(context.sp(1.2), 10, 14);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Text(
        role.isEmpty ? '-' : role[0].toUpperCase() + role.substring(1),
        style: TextStyle(color: fg, fontSize: fs, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final padH = _clamp(context.wp(2.4), 10, 16);
    final padV = _clamp(context.hp(0.7), 6, 10);
    final fs = _clamp(context.sp(1.8), 12, 15);
    final radius = _clamp(context.sp(1.4), 14, 22);
    final borderW = _clamp(context.sp(0.2), 1.6, 2.2);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          border: Border.all(color: kBrand, width: borderW),
          color: selected ? kBrand : Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : kBrand,
            fontWeight: FontWeight.w600,
            fontSize: fs,
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Inputs & Dialogs
/// ─────────────────────────────────────────────────────────────────────────────
Widget field(String label, TextEditingController c, {bool number = false}) {
  return TextField(
    controller: c,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(
        horizontal: _clamp(c.context?.wp(3) ?? 12, 10, 18),
        vertical: _clamp(c.context?.hp(1) ?? 10, 8, 14),
      ),
    ),
  );
}

Widget area(String label, TextEditingController c) {
  return TextField(
    controller: c,
    maxLines: 3,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(
        horizontal: _clamp(c.context?.wp(3) ?? 12, 10, 18),
        vertical: _clamp(c.context?.hp(1) ?? 10, 8, 14),
      ),
    ),
  );
}

/// Helper to access BuildContext inside controllers' widgets safely.
/// If unavailable, defaults are used above.
extension _CtrlCtx on TextEditingController {
  BuildContext? get context {
    // This is a convenience: when used inside build trees, the ambient context is available.
    // If not, callers fall back to sane defaults via ?? in field()/area().
    return WidgetsBinding.instance.focusManager.primaryFocus?.context;
  }
}

Future<bool> confirmDialog({required BuildContext context, required String message}) async {
  final btnFs = _clamp(context.sp(1.8), 12, 15);
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Confirm'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('No', style: TextStyle(fontSize: btnFs))),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text('Yes', style: TextStyle(fontSize: btnFs))),
      ],
    ),
  );
  return res ?? false;
}
