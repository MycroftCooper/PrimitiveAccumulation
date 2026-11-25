import 'package:flutter/material.dart';

enum Skin {
  grove(
    'grove',
    '青瓷存钱罐',
    Color(0xff496b60),
    Color(0xfffaf8f2),
    Color(0xff18292b),
    Color(0xff263f49),
    Color(0xfff1ca86),
  ),
  dusk(
    'dusk',
    '暮紫星光',
    Color(0xff846383),
    Color(0xfffaf6fa),
    Color(0xff251f30),
    Color(0xff44324e),
    Color(0xffeac1a3),
  );

  const Skin(
    this.id,
    this.title,
    this.seed,
    this.paper,
    this.darkPaper,
    this.stage,
    this.gold,
  );
  final String id, title;
  final Color seed, paper, darkPaper, stage, gold;
  static Skin find(String id) =>
      Skin.values.firstWhere((s) => s.id == id, orElse: () => Skin.grove);
}

@immutable
class WealthColors extends ThemeExtension<WealthColors> {
  final Color stage, stageGlow, onStage, gold, glass, ink;
  final List<Color> series;
  const WealthColors(
    this.stage,
    this.stageGlow,
    this.onStage,
    this.gold,
    this.glass,
    this.ink,
    this.series,
  );
  static WealthColors of(BuildContext c) =>
      Theme.of(c).extension<WealthColors>()!;
  @override
  WealthColors copyWith({
    Color? stage,
    Color? stageGlow,
    Color? onStage,
    Color? gold,
    Color? glass,
    Color? ink,
    List<Color>? series,
  }) => WealthColors(
    stage ?? this.stage,
    stageGlow ?? this.stageGlow,
    onStage ?? this.onStage,
    gold ?? this.gold,
    glass ?? this.glass,
    ink ?? this.ink,
    series ?? this.series,
  );
  @override
  WealthColors lerp(covariant WealthColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return WealthColors(
      mix(stage, other.stage),
      mix(stageGlow, other.stageGlow),
      mix(onStage, other.onStage),
      mix(gold, other.gold),
      mix(glass, other.glass),
      mix(ink, other.ink),
      List.generate(series.length, (i) => mix(series[i], other.series[i])),
    );
  }
}

ThemeData wealthTheme(Skin skin, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final paper = dark ? skin.darkPaper : skin.paper;
  final scheme = ColorScheme.fromSeed(
    seedColor: skin.seed,
    brightness: brightness,
  ).copyWith(surface: paper);
  const colors = [
    Color(0xff9679ab),
    Color(0xffc99442),
    Color(0xff55a39c),
    Color(0xff37787a),
    Color(0xffc97a68),
    Color(0xff7286a3),
    Color(0xff909956),
  ];
  final tokens = WealthColors(
    skin.stage,
    Color.lerp(skin.stage, skin.seed, .65)!,
    const Color(0xfffff4dc),
    skin.gold,
    Color.lerp(skin.seed, const Color(0xffe6f0dd), .68)!,
    const Color(0xff253c40),
    colors
        .map(
          (c) => Color.lerp(
            c,
            dark ? Colors.white : skin.seed,
            dark ? 0.22 : 0.08,
          )!,
        )
        .toList(),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    extensions: [tokens],
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans CJK SC',
      'sans-serif',
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: shape,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
    ),
  );
}
