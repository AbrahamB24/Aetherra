/// Cost tables â€” loaded from Supabase game_config on startup.
/// All defaults here; overwritten by GameDataService.load()
class CostConfig {
  static List<double> atk  = [0,2,8,18,32,50,72,98,128,162,200].map((e)=>e.toDouble()).toList();
  static List<double> def  = [0,2.4,9.6,21.6,38.4,60,86.4,117.6,153.6,194.4,240];
  static List<double> rng  = [0,3.25,13,29.25,52,81.25,117,159.25,208,263.25,325];
  static List<double> mob = [
    0,3.5,8.040888,13.080175,18.473111,24.145269,30.050351,36.156442,42.440064,
    48.883136,55.471262,62.192679,69.037577,75.997633,83.065692,90.235526,
    97.501663,104.859251,112.303955,119.831878,127.439494,
  ];
  static List<double> con = [1,1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,2.0];
  static List<double> cp  = [0,10,26.390158,46.555367,69.644045,95.182697,
    122.860351,152.45345,183.791737,216.740222,251.188643];
  static double formulaDivisor = 1.5;

  static void resetToDefaults() {
    atk  = [0,2,8,18,32,50,72,98,128,162,200].map((e)=>e.toDouble()).toList();
    def  = [0,2.4,9.6,21.6,38.4,60,86.4,117.6,153.6,194.4,240];
    rng  = [0,3.25,13,29.25,52,81.25,117,159.25,208,263.25,325];
    mob = [0,3.5,8.040888,13.080175,18.473111,24.145269,30.050351,36.156442,42.440064,
      48.883136,55.471262,62.192679,69.037577,75.997633,83.065692,90.235526,
      97.501663,104.859251,112.303955,119.831878,127.439494];
    con  = [1,1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,2.0];
    cp   = [0,10,26.390158,46.555367,69.644045,95.182697,
      122.860351,152.45345,183.791737,216.740222,251.188643];
    formulaDivisor = 1.5;
  }

  static int calcCost({
    required int a, required int d, required int s,
    required int m, required int str, required String type,
    required int cpVal, required List<String> abilities,
    required Map<String, int> allAbilityCosts,
  }) {
    final mobCost  = mob[m.clamp(0, mob.length - 1)];
    final conMult  = con[str.clamp(0, 10)];
    final cpCost   = cp[cpVal.clamp(0, 10)];
    final abCost   = abilities.fold<double>(
      0, (s2, name) => s2 + (allAbilityCosts[name] ?? 0));
    final sum     = atk[a.clamp(0,10)] + def[d.clamp(0,10)] +
      rng[s.clamp(0,10)] + mobCost + cpCost + abCost;
    final divisor = formulaDivisor > 0 ? formulaDivisor : 1.5;
    final total   = sum * conMult / divisor;
    return (total / 5).round() * 5;
  }
}