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
- **Colors:** Emerald Green (#10B981) is the primary/accent color in BOTH light and dark modes. Dark mode should use deep grays (#121212, #1E1E1E). Light mode should use off-whites. No harsh or neon colors.
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
  - On Mobile (width < 900): Use a Drawer or BottomNavigationBar, and convert wide DataTables into scrollable Lists or Cards.
- **Platform-Specific Code:** Use `Platform.isWindows` or `Platform.isAndroid` (from `dart:io`) ONLY when absolutely necessary (e.g., file paths, barcode scanner logic). Always handle both cases gracefully.
- **Packages:** Ensure any package added to `pubspec.yaml` supports both Windows and Android. Avoid mobile-only packages unless guarded by platform checks.
- **Build Configuration:** Ensure `flutter build windows` and `flutter build apk` are configured correctly in the project.