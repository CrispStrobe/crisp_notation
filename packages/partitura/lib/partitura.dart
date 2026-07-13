/// Music notation rendering for Flutter with first-class interactivity.
///
/// [StaffView] renders a `Score` (from `partitura_core`, re-exported here)
/// using the bundled Bravura SMuFL font; `InteractiveStaff` adds hit
/// testing, selection and drag. See HANDOVER.md at the repository root for
/// the full contract.
library;

export 'package:partitura_core/partitura_core.dart';

export 'src/interaction/interactive_staff.dart';
export 'src/interaction/staff_target.dart';
export 'src/rendering/bravura.dart';
export 'src/rendering/font_licenses.dart' show registerBundledFontLicenses;
export 'src/rendering/grand_staff_view.dart';
export 'src/rendering/multi_part_view.dart';
export 'src/rendering/multi_system_view.dart';
export 'src/rendering/music_font.dart';
export 'src/rendering/png_export.dart';
export 'src/rendering/score_page_view.dart';
export 'src/rendering/smufl_glyphs.dart';
export 'src/rendering/staff_system_view.dart';
export 'src/rendering/staff_view.dart';
export 'src/rendering/tab_staff_view.dart';
export 'src/rendering/theme.dart';
