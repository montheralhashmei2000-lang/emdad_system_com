# CLAUDE.md - Project Constitution & AI Guidelines

## 1. Project Overview
- **Name:** Supply Chain & Inventory Management System (نظام الإمداد والتموين)
- **Tech Stack:** Flutter (Dart), targeting Web/Desktop/Mobile.
- **Language:** Arabic (RTL) - All UI text must be in Arabic. Ensure proper RTL alignment for all components, including icons and padding.
- **Goal:** Achieve a world-class, modern, professional UI/UX similar to premium ERP systems like Onyx Pro.

## 2. Architecture & Code Standards
- **State Management:** `provider` (^6.1.2) is used only as dependency injection (`context.read<AuthService>()`, `AppDatabase`, `AutoSyncService`, `ImdNav`); services that notify use `ChangeNotifier`. Screen-local UI state uses `setState`. Do NOT add Riverpod/Bloc/GetX; follow this existing pattern.
- **Separation of Concerns:** Keep UI widgets separate from business logic. Shared UI components live in `lib/core/ui/` (prefix `Imd`, e.g. `ImdTable`, `ImdChip`, `ImdButton`), screens in `lib/features/`, theme in `lib/core/theme/`.
- **Reusability:** NEVER build UI components inline if they are used in more than one place. Always create reusable widgets in `lib/core/ui/` (do NOT create `lib/widgets/`). Improve an existing `Imd*` component before adding a parallel one, and keep its public signature backward compatible.
- **Performance:** Use `const` constructors wherever possible. Avoid unnecessary rebuilds. Use `ListView.builder` for long lists.
- **Code Quality:** Write clean, self-documenting code. Add comments in English for complex logic, but UI text must remain Arabic.

## 3. UI/UX Design System Rules (CRITICAL)
- **Theme Awareness:** The app must support Light Mode, Dark Mode, and System Mode. NEVER hardcode colors (e.g., `Colors.black`). ALWAYS use `Theme.of(context).colorScheme.xxx` or the `ImdColors` theme extension (`context.imd.xxx`).
- **Colors:** Emerald Green is the primary/accent color in both modes, in the shade each mode needs for contrast: **#047857 in Light Mode** (hover #065F46) and **#10B981 in Dark Mode** (hover #34D399). Dark mode uses deep grays (#171717 background, #212121 surface). Light mode uses off-whites (#F7F7F8 background, #FFFFFF surface). No harsh or neon colors. These are defined once in `ImdColors.light` / `ImdColors.dark` (`lib/core/ui/imd_tokens.dart`) — read them from `context.imd`, never re-declare a hex.
- **Typography:** Use the bundled local font `IBMPlexSansArabic` (`ImdSizes.font`) for all text. Do NOT add `google_fonts`.
- **Spacing & Shapes:** Use consistent padding (8, 16, 24) and rounded corners (`BorderRadius.circular(12)`) for cards, buttons, and input fields.
- **Data Tables:** Tables must be dense, professional, and use sticky headers. Hover effects on rows are required. Use `StatusBadge` widgets for statuses (e.g., "لم تُضبط بعد" in soft orange, "مضبوط" in soft green).
- **Data Entry Screens (e.g., Receipts):** Optimize for speed. Use sticky headers for barcode scanners and sticky footers for action buttons (Save, Approve, Print). Auto-save or single-save buttons are preferred over per-row save buttons.
- **Feedback & Loading:** Use `Shimmer` for loading states. Use `SnackBar` or `MaterialBanner` for success/error feedback. Do not use generic `AlertDialog` for success messages.

## 4. AI Workflow Rules
- **File Path Confirmation:** Always ask for or confirm the exact target file path before making edits (e.g., `lib/screens/receipts_screen.dart`).
- **Error Handling:** If a change fails, breaks the build, or introduces linter errors, revert the modification immediately and attempt an alternative approach.
- **Incremental Changes:** When refactoring a screen, do it incrementally (e.g., first the layout, then the theme, then the logic) to avoid breaking the entire file at once.
- **Testing:** After modifying a widget or screen, verify that it compiles and does not break RTL alignment.
## 5. Cross-Platform & Responsive Rules (EXE & APK)
- **Target Platforms:** The app MUST compile and run flawlessly on both Android (APK) and Windows (EXE).
- **Adaptive Layouts:** NEVER use fixed widths/heights (e.g., `width: 300`). ALWAYS use `LayoutBuilder`, `MediaQuery`, or `Expanded/Flexible` to make layouts adapt to screen size.
- **Single Breakpoint:** The desktop/mobile switch is **900px** everywhere (replacing the old 680/920 split in `ImdBp`). Do not introduce other breakpoints.
- **Desktop vs Mobile UI:**
  - On Desktop (width > 900): Use a permanent Sidebar (NavigationRail), wide DataTables, and keyboard shortcuts.
  - On Mobile (width < 900): Use a Drawer or BottomNavigationBar. `ImdTable` stays a **table** (natural width, horizontal scroll, first column frozen via `freezeFirst`) — NOT cards. `cards: true` is an explicit opt-in for small tables only.
- **Shell (desktop):** open pages live as MDI tabs (`ImdPageTabs`, max 8 per section) kept alive by `ImdPageHost` (Offstage + TickerMode + ExcludeFocus). A hidden page is flagged stale (orange dot + `ImdStaleBanner`) when the DB changes — never auto-reloaded (a half-filled voucher must not be lost). Mobile keeps a single page. The bottom `ImdStatusBar` (clock, connection from `AutoSyncService`, record count from `ImdRecordScope`, density + classic toggles) is desktop-only; the sync pill lives there, not in the topbar.
- **Sections:** Supply (emerald `#047857`) and Fuel (burnt orange, `ImdColors.fuelLight/fuelDark`, `AppTheme.fuelSection`) share the same shell/tables/fields but have independent palettes. Each section keeps its own tabs and both stay mounted when switching (`_SpaceState` in `home_shell.dart`; covered by `test/section_switch_test.dart`).
- **Density & style:** `ImdDensity` (high-density mode; touch targets never shrink) and `ImdStyle` (optional classic flat style: radius 2, no shadows, Tahoma, `ImdColors.classicLight`) are static switches read through `ImdSizes`/`ImdDensity` getters and applied by re-marking the tree (`ImdDensity.rebuildAll`). Never hardcode a radius/padding that should follow them.
- **Table tools:** pass `ImdTable.values` (raw cell values, same shape as `rows`) to enable instant Find, column filters, drag-to-group panel and the record count. Use it on large read tables (items, suppliers, balances, movements); NOT on small tables or entry tables. `onRowTap`/`rowMenu`/`rowColor` always receive the ORIGINAL row index. An empty table keeps its header plus a small grey row.
- **Selects:** `ImdSelect` opens a large searchable dialog (never the small dropdown).
- **Platform-Specific Code:** Use `Platform.isWindows` or `Platform.isAndroid` (from `dart:io`) ONLY when absolutely necessary (e.g., file paths, barcode scanner logic). Always handle both cases gracefully.
- **Packages:** Ensure any package added to `pubspec.yaml` supports both Windows and Android. Avoid mobile-only packages unless guarded by platform checks.
- **Build Configuration:** Ensure `flutter build windows` and `flutter build apk` are configured correctly in the project.
- **Entry Tables:** Item-entry tables (receipts, issues, transfers, returns, orders, opening balances, stocktake count) MUST use `ImdEntryTable`: row height equals the compact field height (`ImdSizes.compactField`), rows touch each other (grid line only), read-only cells (balance) are field-shaped, and buttons inside `ImdCompact` take the field height automatically. Never add per-row vertical padding. Desktop cells are **flush** (`ImdTable.flushCells`, `ImdCompact(flush: true)`): zero cell padding, fields/buttons with square corners and no own border (the grid line separates cells), and a fixed height equal to the row. A dropdown + quick-add `+` button MUST use `ImdInputGroup` (one frame, same height). Page-header tabs and action buttons go through `ImdPageTitle.actions` (`ImdActionRow`, height `ImdSizes.barControl`) so they share one baseline.
- **Embedded Screens:** A full screen shown as a section inside another screen (e.g. Settings sections) is wrapped in `ImdEmbedScope`; `ImdPage`, `ImdPageTitle`, `ImdPageBack` and `ImdStickyPage` adapt automatically. Do not add a sidebar item for something that belongs as a section of an existing screen.
- **Mobile Verification:** `test/mobile_layout_test.dart` sweeps every page at 320/360/740(landscape)/800 widths and 1.3 text scale with the real font and fails on any overflow. New pages must be added to its list. Text scale is clamped to `kImdMaxTextScale` (1.3).

