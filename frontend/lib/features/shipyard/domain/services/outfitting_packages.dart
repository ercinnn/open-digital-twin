import '../entities/production_entities.dart';
import 'draft_schedule.dart';

/// Draft of the afloat outfitting work packages of a hull: rows to insert and,
/// for a hull that has a single generic outfitting row, the plan update that
/// turns that row into its first package.
class OutfittingPlan {
  const OutfittingPlan({this.create = const [], this.convert, this.problems = const [], this.start, this.end});

  const OutfittingPlan.problems(List<String> problems) : this(problems: problems);

  final List<ActivityDraft> create;

  /// The generic outfitting row and its new plan (same id and code, so its
  /// inspections, permits and bookings stay linked).
  final ({ProductionActivity row, ActivityDraft draft})? convert;

  final List<String> problems;

  /// Outfitting window the packages are spread over.
  final DateTime? start;
  final DateTime? end;

  bool get isValid => problems.isEmpty && (create.isNotEmpty || convert != null);

  /// Every package row of the plan, converted row first.
  List<ActivityDraft> get rows => [if (convert != null) convert!.draft, ...create];
}

/// Afloat outfitting split into system work packages, spread over the
/// outfitting window (launching -> commissioning) by a typical sequence:
/// outfitting steel and deck machinery first, machinery and piping through
/// most of the window, electrical and accommodation later, final painting at
/// the end. All packages are worked on board at the quay.
class OutfittingPackages {
  const OutfittingPackages._();

  /// Shortest outfitting window the packages are spread over (days).
  static const minWindowDays = 7;

  /// Start / end of each package as a fraction of the outfitting window.
  static const template = <WorkPackage, (double, double)>{
    WorkPackage.outfittingSteel: (0.00, 0.45),
    WorkPackage.deckMachinery: (0.10, 0.60),
    WorkPackage.machinery: (0.05, 0.70),
    WorkPackage.piping: (0.05, 0.85),
    WorkPackage.electrical: (0.15, 1.00),
    WorkPackage.accommodation: (0.25, 0.95),
    WorkPackage.painting: (0.70, 1.00),
  };

  /// The generic row is converted into this package: the outfitting ITP point
  /// (pressure test of the piping systems) is already linked to it.
  static const convertedPackage = WorkPackage.piping;

  /// Planned window of [package] inside [start] .. [end] (at least one day).
  static (DateTime, DateTime) windowOf(WorkPackage package, DateTime start, DateTime end) {
    final days = daysBetween(start, end);
    final (f0, f1) = template[package]!;
    final s = addDays(start, (days * f0).round());
    final e = addDays(start, (days * f1).round());
    return (s, e.isAfter(s) ? e : addDays(s, 1));
  }

  /// Outfitting window recovered from planned package rows: the window the
  /// package with the widest template share ([template]) was spread over (so
  /// packages added later line up with it, also after it was moved).
  static (DateTime, DateTime) windowFrom(Iterable<ProductionActivity> packageRows) {
    double share(ProductionActivity a) {
      final (f0, f1) = template[a.workPackage]!;
      return f1 - f0;
    }

    final ref = packageRows.reduce((a, b) => share(b) > share(a) ? b : a);
    final (f0, f1) = template[ref.workPackage]!;
    final total = (daysBetween(ref.plannedStart, ref.plannedEnd) / (f1 - f0)).round();
    final start = addDays(ref.plannedStart, -(total * f0).round());
    return (start, addDays(start, total));
  }

  static ActivityDraft _draft(
    Hull hull,
    WorkPackage package,
    DateTime start,
    DateTime end, {
    required String code,
    required int sortOrder,
    String? location,
    Map<String, String> departmentIdByCode = const {},
  }) {
    final (s, e) = windowOf(package, start, end);
    return ActivityDraft(
      projectId: hull.projectId,
      hullId: hull.id,
      code: code,
      name: '${hull.hullNo} ${package.label}',
      stage: ProductionStage.outfitting,
      plannedStart: s,
      plannedEnd: e,
      locationNodeId: location ?? stageDefaultLocations[ProductionStage.outfitting],
      sortOrder: sortOrder,
      workPackage: package,
      departmentId: departmentIdByCode[package.departmentCode],
    );
  }

  /// One row per package in [packages] (template order) over [start] .. [end].
  /// New codes are added to [codes].
  static List<ActivityDraft> rows(
    Hull hull,
    DateTime start,
    DateTime end, {
    Iterable<WorkPackage> packages = WorkPackage.values,
    required Set<String> codes,
    required int firstSortOrder,
    String? location,
    Map<String, String> departmentIdByCode = const {},
  }) {
    final wanted = packages.toSet();
    var sort = firstSortOrder;
    return [
      for (final p in WorkPackage.values)
        if (wanted.contains(p))
          _draft(
            hull,
            p,
            start,
            end,
            code: _take(workPackageCodeFor(hull.hullNo, p, codes), codes),
            sortOrder: sort++,
            location: location,
            departmentIdByCode: departmentIdByCode,
          ),
    ];
  }

  static String _take(String code, Set<String> codes) {
    codes.add(code);
    return code;
  }

  /// Packages for a hull that already has a schedule ([activities] of the
  /// project). Packages already planned are skipped (their window is reused);
  /// a single, not yet started generic outfitting row becomes the
  /// [convertedPackage] and gives the window; without an outfitting row the
  /// window follows the draft template from the launching row / milestones.
  static OutfittingPlan forHull(
    Hull hull,
    List<ProductionActivity> activities, {
    Set<String> existingCodes = const {},
    int firstSortOrder = 1,
    Map<String, String> departmentIdByCode = const {},
  }) {
    if (hull.isRepair) {
      return const OutfittingPlan.problems(['Repairs have no afloat outfitting packages.']);
    }
    final own = activities.where((a) => a.hullId == hull.id && a.componentId == null).toList()
      ..sort((a, b) {
        final c = a.plannedStart.compareTo(b.plannedStart);
        return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
      });
    final outfitting = own.where((a) => a.stage == ProductionStage.outfitting).toList();
    final planned = {
      for (final a in outfitting)
        if (a.workPackage != null) a.workPackage!,
    };
    final missing = [
      for (final p in WorkPackage.values)
        if (!planned.contains(p)) p,
    ];
    if (missing.isEmpty) {
      return OutfittingPlan.problems(['Every work package of ${hull.hullNo} is already planned.']);
    }
    final codes = {...existingCodes};

    DateTime start;
    DateTime end;
    ProductionActivity? generic;
    if (planned.isNotEmpty) {
      (start, end) = windowFrom(outfitting.where((a) => a.workPackage != null));
    } else if (outfitting.isNotEmpty) {
      generic = outfitting.first;
      if (generic.isDone) {
        return OutfittingPlan.problems(['${generic.code} (afloat outfitting) is already reported finished.']);
      }
      if (generic.actualStart != null) {
        return OutfittingPlan.problems([
          '${generic.code} (afloat outfitting) has already started; add packages by hand (Plan > Add activity).',
        ]);
      }
      start = generic.plannedStart;
      end = generic.plannedEnd;
    } else {
      final launching = own.where((a) => a.stage == ProductionStage.launching).lastOrNull;
      final l = launching?.plannedStart ?? hull.launchingDate;
      final d = hull.contractDeliveryDate ?? hull.forecastDeliveryDate;
      if (l == null || d == null) {
        return OutfittingPlan.problems([
          if (l == null) 'Enter the launching date or draft the schedule of ${hull.hullNo} first.',
          if (d == null) 'Enter the contract delivery date.',
        ]);
      }
      (start, end) = DraftSchedule.outfittingWindow(l, d);
      if (launching != null && launching.plannedEnd.isAfter(start)) {
        start = launching.plannedEnd;
      }
    }
    if (daysBetween(start, end) < minWindowDays) {
      return OutfittingPlan.problems([
        'The afloat outfitting window ${formatDate(start)} → ${formatDate(end)} is shorter than $minWindowDays days.',
      ]);
    }

    final location = generic?.locationNodeId ?? outfitting.firstOrNull?.locationNodeId;
    ({ProductionActivity row, ActivityDraft draft})? convert;
    if (generic != null) {
      convert = (
        row: generic,
        draft: _draft(
          hull,
          convertedPackage,
          start,
          end,
          code: generic.code,
          sortOrder: generic.sortOrder,
          location: location,
          departmentIdByCode: departmentIdByCode,
        ),
      );
    }
    final create = rows(
      hull,
      start,
      end,
      packages: missing.where((p) => convert == null || p != convertedPackage),
      codes: codes,
      firstSortOrder: firstSortOrder,
      location: location,
      departmentIdByCode: departmentIdByCode,
    );
    return OutfittingPlan(create: create, convert: convert, start: start, end: end);
  }
}
