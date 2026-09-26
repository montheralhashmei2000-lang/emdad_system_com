/// سطرٌ في خطة توزيع الاستحقاق المطبوعة.
class FuelPlanRow {
  const FuelPlanRow({
    required this.n,
    required this.unit,
    required this.location,
    required this.weekly,
    required this.monthly,
    required this.notes,
  });

  final int n;
  final String unit;
  final String location;
  final double weekly;
  final double monthly;
  final String notes;
}
