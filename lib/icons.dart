import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The icon set, grouped the way money gets spent.
///
/// Lucide via `lucide_icons_flutter` — an icon *font*, so an icon costs a
/// codepoint rather than an asset and `--tree-shake-icons` strips every glyph
/// nothing here names.
///
/// ponytail: the whole package for ~120 icons, ~0.7 MB of the release APK. If
/// that ever matters, generate a private class holding only the codepoints
/// below and drop the dependency — the keys here are the interface, so nothing
/// outside this file would change.
///
/// Every entry is stored by its key, never by codepoint: a package upgrade
/// that renumbers glyphs must not silently repaint everyone's categories.
const iconGroups = <String, Map<String, IconData>>{
  'Money': {
    'wallet': LucideIcons.wallet,
    'banknote': LucideIcons.banknote,
    'coins': LucideIcons.coins,
    'piggy-bank': LucideIcons.piggyBank,
    'credit-card': LucideIcons.creditCard,
    'landmark': LucideIcons.landmark,
    'receipt': LucideIcons.receipt,
    'trending-up': LucideIcons.trendingUp,
    'trending-down': LucideIcons.trendingDown,
    'chart-pie': LucideIcons.chartPie,
    'hand-coins': LucideIcons.handCoins,
    'gem': LucideIcons.gem,
    'vault': LucideIcons.vault,
    'arrow-left-right': LucideIcons.arrowLeftRight,
  },
  'Food': {
    'utensils': LucideIcons.utensils,
    'coffee': LucideIcons.coffee,
    'pizza': LucideIcons.pizza,
    'sandwich': LucideIcons.sandwich,
    'shopping-basket': LucideIcons.shoppingBasket,
    'shopping-cart': LucideIcons.shoppingCart,
    'apple': LucideIcons.apple,
    'milk': LucideIcons.milk,
    'cake': LucideIcons.cake,
    'beer': LucideIcons.beer,
    'ice-cream': LucideIcons.iceCreamCone,
    'cooking-pot': LucideIcons.cookingPot,
  },
  'Home': {
    'house': LucideIcons.house,
    'bed': LucideIcons.bed,
    'sofa': LucideIcons.sofa,
    'lightbulb': LucideIcons.lightbulb,
    'droplet': LucideIcons.droplet,
    'flame': LucideIcons.flame,
    'wifi': LucideIcons.wifi,
    'plug': LucideIcons.plug,
    'wrench': LucideIcons.wrench,
    'brush': LucideIcons.brush,
    'trash': LucideIcons.trash2,
    'key': LucideIcons.key,
  },
  'Transport': {
    'car': LucideIcons.car,
    'bus': LucideIcons.bus,
    'train': LucideIcons.trainFront,
    'bike': LucideIcons.bike,
    'plane': LucideIcons.plane,
    'fuel': LucideIcons.fuel,
    'ship': LucideIcons.ship,
    'taxi': LucideIcons.carTaxiFront,
    'parking': LucideIcons.circleParking,
    'map-pin': LucideIcons.mapPin,
  },
  'Life': {
    'heart-pulse': LucideIcons.heartPulse,
    'pill': LucideIcons.pill,
    'stethoscope': LucideIcons.stethoscope,
    'graduation-cap': LucideIcons.graduationCap,
    'book': LucideIcons.bookOpen,
    'baby': LucideIcons.baby,
    'users': LucideIcons.users,
    'dog': LucideIcons.dog,
    'shirt': LucideIcons.shirt,
    'scissors': LucideIcons.scissors,
    'dumbbell': LucideIcons.dumbbell,
    'gift': LucideIcons.gift,
    'shield': LucideIcons.shield,
    'phone': LucideIcons.phone,
  },
  'Fun': {
    'film': LucideIcons.film,
    'music': LucideIcons.music,
    'gamepad': LucideIcons.gamepad2,
    'tv': LucideIcons.tv,
    'ticket': LucideIcons.ticket,
    'palette': LucideIcons.palette,
    'camera': LucideIcons.camera,
    'headphones': LucideIcons.headphones,
    'tent': LucideIcons.tent,
    'party-popper': LucideIcons.partyPopper,
    'sparkles': LucideIcons.sparkles,
  },
  'Work': {
    'briefcase': LucideIcons.briefcaseBusiness,
    'laptop': LucideIcons.laptop,
    'building': LucideIcons.building2,
    'mail': LucideIcons.mail,
    'file-text': LucideIcons.fileText,
    'printer': LucideIcons.printer,
    'calendar': LucideIcons.calendar,
    'clock': LucideIcons.clock,
    'handshake': LucideIcons.handshake,
  },
  'Other': {
    'tag': LucideIcons.tag,
    'star': LucideIcons.star,
    'circle': LucideIcons.circle,
    'box': LucideIcons.box,
    'package': LucideIcons.package,
    'leaf': LucideIcons.leaf,
    'sprout': LucideIcons.sprout,
    'globe': LucideIcons.globe,
    'sun': LucideIcons.sun,
    'moon': LucideIcons.moon,
    'umbrella': LucideIcons.umbrella,
    'zap': LucideIcons.zap,
  },
};

/// Every icon by key, flattened. Built once — rebuilding a 120-entry map per
/// row per frame is the kind of thing that only shows up on a long ledger.
final iconByKey = <String, IconData>{
  for (final group in iconGroups.values) ...group,
};

/// Which group a key belongs to, for the picker's search results.
final groupOfIcon = <String, String>{
  for (final entry in iconGroups.entries)
    for (final key in entry.value.keys) key: entry.key,
};

/// A category with nothing chosen.
const defaultIcon = 'tag';

/// The glyph for [key], or the default when the key is unknown — a stored icon
/// can outlive a rename, and a category whose icon vanished should still draw.
IconData iconFor(String key) =>
    iconByKey[key] ?? iconByKey[defaultIcon] ?? LucideIcons.tag;
