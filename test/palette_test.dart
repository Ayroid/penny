import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penny/clock.dart';
import 'package:penny/theme.dart';

/// [fg] at [alpha] painted over [bg] — what a tinted well actually resolves to.
Color over(Color fg, double alpha, Color bg) =>
    Color.alphaBlend(fg.withValues(alpha: alpha), bg);

/// What `onAccent()` computes, without a BuildContext.
Color onAccentOf(Color accent) =>
    contrastBetween(navy, accent) >= contrastBetween(Colors.white, accent)
    ? navy
    : Colors.white;

void main() {
  group('the brand accent', () {
    test('on-accent computes to navy, not white, in both themes', () {
      // The whole reason the design system says to compute it. Wick's flame is
      // dark enough that hardcoding white nearly works; the sprout is not, and
      // a 15px/700 button label on it needs 4.5:1.
      expect(onAccentOf(sprout), navy);
      expect(onAccentOf(sproutDark), navy);
    });

    test('white on the sprout fails — nothing may hardcode it', () {
      expect(contrastBetween(Colors.white, sprout), lessThan(4.5));
      expect(contrastBetween(Colors.white, sproutDark), lessThan(4.5));
    });

    test('navy on the sprout carries a button label', () {
      expect(contrastBetween(navy, sprout), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(navy, sproutDark), greaterThanOrEqualTo(4.5));
    });
  });

  group('text on the page', () {
    test('body text passes in both themes', () {
      expect(contrastBetween(navy, warmBg), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkInk, darkBg), greaterThanOrEqualTo(4.5));
    });

    test('secondary text passes in both themes', () {
      expect(contrastBetween(navySoft, warmBg), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkMuted, darkBg), greaterThanOrEqualTo(4.5));
    });

    test('body text passes on a sunk fill — inputs, the segmented track', () {
      expect(contrastBetween(navy, warmSunk), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkInk, darkSunk), greaterThanOrEqualTo(4.5));
    });
  });

  group('the coin', () {
    // Income is drawn in the sprout and expense in the coin, side by side in
    // every chart. Green-vs-orange is the classic deuteranope confusion pair,
    // so the two have to be told apart by lightness and not only by hue.
    test('sprout and coin are separated in luminance', () {
      expect(contrastBetween(sprout, coin), greaterThanOrEqualTo(1.4));
      expect(contrastBetween(sproutDark, coinDark), greaterThanOrEqualTo(1.4));
    });

    test('a coin bar reads against the page — WCAG 1.4.11 for graphics', () {
      expect(contrastBetween(coin, warmBg), greaterThanOrEqualTo(3.0));
      expect(contrastBetween(coinDark, darkBg), greaterThanOrEqualTo(3.0));
    });

    // The sprout cannot reach 3:1 on cream, and this is arithmetic rather than
    // taste. Navy on the sprout needs its luminance >= .2889 to clear 4.5:1
    // for a button label; 3:1 against cream needs it <= .2824. No green
    // satisfies both — the window is empty by .0065. Wick's flame slips
    // through at 3.11 only because orange is the darker hue.
    //
    // The button is where the sprout has to be right, so it wins, and a sprout
    // bar is never the only signal: every bar carries its amount as text and
    // sits against a labelled axis. Dark mode has no such collision.
    test('a sprout bar is a documented exception on cream', () {
      expect(
        contrastBetween(sprout, warmBg),
        allOf(greaterThanOrEqualTo(2.4), lessThan(3.0)),
      );
      expect(contrastBetween(sproutDark, darkBg), greaterThanOrEqualTo(3.0));
    });

    // The coin gives up carrying text so it can keep the gap above. This test
    // exists to make that a decision rather than an oversight: if a future
    // tone passes both, the "amounts sit beside the bar" rule can be relaxed.
    test('nothing legible sits on a coin fill — by construction', () {
      for (final c in [coin, coinDark]) {
        expect(contrastBetween(navy, c), lessThan(4.5));
        expect(contrastBetween(Colors.white, c), lessThan(4.5));
      }
    });

    test('the soft green wash carries ink, and swaps which one', () {
      // A goal's percentage pill and the line under a finished goal's bar.
      // The deep tone on cream; the accent at night, where the deep tone is
      // 2.6:1 against the dark wash and would fail an 11px label outright.
      expect(
        contrastBetween(sproutDeep, sproutSoft),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastBetween(sproutDark, sproutSoftDark),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastBetween(sproutDeepDark, sproutSoftDark),
        lessThan(4.5),
        reason: 'the swap is measured, not a preference',
      );
    });

    test('the deep sprout carries white, which the accent cannot', () {
      for (final c in [sproutDeep, sproutDeepDark]) {
        expect(contrastBetween(Colors.white, c), greaterThanOrEqualTo(4.5));
      }
      expect(contrastBetween(Colors.white, sprout), lessThan(4.5));
    });

    test('the coin at wash strength does carry ink', () {
      expect(contrastBetween(navy, coinSoft), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(darkInk, coinSoftDark), greaterThanOrEqualTo(4.5));
    });
  });

  group('the sky over the balance', () {
    // Four cuts of the range, and the boundaries between them are the same
    // ones the greeting reads — a card that says good evening under a midday
    // sun is the bug this pins.
    test('follows the clock, like the greeting does', () {
      final previous = useFixedClock(DateTime(2026, 9, 17, 8));
      addTearDown(() => clock = previous);

      for (final (hour, image, hello) in [
        (7, 'morning', 'Good morning'),
        (13, 'afternoon', 'Good afternoon'),
        (18, 'evening', 'Good evening'),
        (23, 'night', 'Good evening'),
      ]) {
        useFixedClock(DateTime(2026, 9, 17, hour));
        expect(landingImage(), 'assets/images/${image}_landing.png');
        expect(greeting(), hello);
      }
    });
  });

  group('the spend heatmap', () {
    // Penny's heatmap is brand-hued: one colour for the whole month, unlike
    // Wick's per-habit grids. So there is exactly one pair to hold up, not 21.
    for (final dark in [true, false]) {
      final where = dark ? 'dark' : 'light';
      final accent = dark ? sproutDark : sprout;
      // The top of the ramp: the deep tone on cream, the lit sprout at night
      // — see the note in home.dart's `_Cell`.
      final lit = dark ? sproutDark : sproutDeep;
      final ground = dark ? darkBg : warmBg;

      // The card, and the well the cells are read against. At night that well
      // is a dark panel; on cream the grid sits straight on the card so the
      // card's hover and press ink reach it — see `gridWell`.
      final well = over(accent, dark ? 0.07 : 0.035, ground);
      final unlit = over(accent, dark ? 0.16 : 0.38, well);

      test('$where: a spent day is distinct from an empty one', () {
        // Cream used to be the documented exception here — accent against a
        // wash of itself is a saturation gap, not a luminance one, and topped
        // out near 1.9. Drawing the busy end in the deep tone instead settles
        // it at 6:1 and the exception is gone.
        expect(
          contrastBetween(lit, unlit),
          greaterThanOrEqualTo(3.0),
          reason: '$where: a spent cell is not distinct from an empty one',
        );
      });

      test('$where: a figure reads at every step of the ramp', () {
        // The calendar writes a day's net inside the shaded cell, so the ink
        // is picked per cell — see `_Cell`. Walked across the ramp because the
        // ends are the easy part: the crossover in the middle is where a
        // single hardcoded ink fails, and it is also where the brand's navy
        // fails, which is why this one cell is drawn in black and white.
        //
        // This is also the reason the figure is not green-for-up and
        // red-for-down: neither tone survives its own ground here, and the
        // direction is carried by the minus sign instead.
        var navyFails = false;
        for (var i = 0; i <= 20; i++) {
          final cell = Color.lerp(unlit, lit, i / 20)!;
          final ink =
              contrastBetween(Colors.black, cell) >=
                  contrastBetween(Colors.white, cell)
              ? Colors.black
              : Colors.white;
          expect(
            contrastBetween(ink, cell),
            greaterThanOrEqualTo(4.5),
            reason: '$where: a 9.5px figure fails at ${i * 5}% of the ramp',
          );
          if (contrastBetween(onAccentOf(cell), cell) < 4.5) navyFails = true;
        }
        expect(
          navyFails,
          isTrue,
          reason:
              '$where: navy now survives the ramp — the cell can go back '
              'to the brand ink',
        );
      });

      test('$where: month and weekday labels survive the well', () {
        final label = dark ? Colors.white : over(navySoft, 0.85, well);
        expect(
          contrastBetween(label, well),
          greaterThanOrEqualTo(4.5),
          reason: '$where: grid furniture is lost in the well',
        );
      });
    }
  });

  group('category swatches', () {
    // Penny draws these as icon-tile fills, card hairlines and category bars —
    // never as a lit/unlit grid pair, which is why that assertion lives with
    // the heatmap above and not here.
    for (final swatch in catColors) {
      test('${swatch.name}: a glyph reads on its own fill', () {
        final ink = onAccentOf(swatch.value);
        expect(
          contrastBetween(ink, swatch.value),
          greaterThanOrEqualTo(4.5),
          reason: '${swatch.name}: the glyph fails on its own fill',
        );
      });

      test('${swatch.name}: chip text survives its own dark well', () {
        // At night a chip is accent ink on a faint well of itself. On cream it
        // inverts to the normal foreground — see `onTint`.
        final darkWell = over(
          swatch.value,
          0.15,
          over(swatch.value, 0.07, darkBg),
        );
        expect(
          contrastBetween(swatch.value, darkWell),
          greaterThanOrEqualTo(4.5),
          reason: '${swatch.name}: chip text is lost in its own well',
        );
      });
    }

    test('the palette is intact — 21 distinct swatches, 3 rows of 7', () {
      expect(catColors, hasLength(21));
      expect(catColors.length % 7, 0);
      expect(catColors.map((c) => c.name).toSet(), hasLength(21));
      expect(catColors.map((c) => c.value).toSet(), hasLength(21));
    });

    test('the palette is light throughout — which is why the well is dark', () {
      // If a swatch ever arrives dark enough to read on cream, the dark well
      // stops being necessary for it and this assumption needs revisiting.
      for (final c in catColors) {
        expect(
          c.value.computeLuminance(),
          greaterThan(0.25),
          reason: '${c.name} is darker than the palette this was built for',
        );
      }
    });

    test('the default is a real swatch', () {
      expect(defaultCatColor, inInclusiveRange(0, catColors.length - 1));
    });

    test('an out-of-range index clamps instead of crashing', () {
      // Stored data is a hand-editable JSON export; a bad index must not be
      // able to take the app down.
      for (final i in [-99, -1, 21, 9999]) {
        expect(() => catColorAt(i), returnsNormally);
      }
      expect(catColorAt(-1), catColors.first.value);
      expect(catColorAt(9999), catColors.last.value);
    });
  });
}
