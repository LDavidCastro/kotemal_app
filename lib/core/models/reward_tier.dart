class RewardTier {
  final int pointsRequired;
  final double discountAmount;
  final double minFoodSubtotal;
  final String title;

  const RewardTier({
    required this.pointsRequired,
    required this.discountAmount,
    required this.minFoodSubtotal,
    required this.title,
  });

  static RewardTier? bestAvailableFor(int points) {
    RewardTier? best;
    for (final tier in kRewardTiers) {
      if (points >= tier.pointsRequired) {
        best = tier;
      }
    }
    return best;
  }
}

const List<RewardTier> kRewardTiers = [
  RewardTier(
    pointsRequired: 150,
    discountAmount: 20,
    minFoodSubtotal: 30,
    title: 'Q20.00 de descuento',
  ),
  RewardTier(
    pointsRequired: 200,
    discountAmount: 25,
    minFoodSubtotal: 35,
    title: 'Q25.00 de descuento',
  ),
  RewardTier(
    pointsRequired: 275,
    discountAmount: 35,
    minFoodSubtotal: 50,
    title: 'Q35.00 de descuento',
  ),
  RewardTier(
    pointsRequired: 450,
    discountAmount: 50,
    minFoodSubtotal: 70,
    title: 'Q50.00 de descuento',
  ),
];
