import 'package:flutter/material.dart';

class LauncherContentConfig {
  const LauncherContentConfig({
    required this.homeTab,
    this.tabs = const <LauncherContentPage>[],
  });

  final LauncherContentPage homeTab;
  final List<LauncherContentPage> tabs;

  LauncherContentPage? pageById(String? id) {
    final normalized = (id ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return homeTab;
    if (homeTab.id.toLowerCase() == normalized) return homeTab;
    for (final tab in tabs) {
      if (tab.id.toLowerCase() == normalized) return tab;
    }
    return null;
  }

  bool hasPage(String? id) {
    return pageById(id) != null;
  }

  factory LauncherContentConfig.fromJson(
    Map<String, dynamic> json, {
    required String repositoryUrl,
    required String discordInviteUrl,
  }) {
    final fallback = LauncherContentConfig.defaults(
      repositoryUrl: repositoryUrl,
      discordInviteUrl: discordInviteUrl,
    );
    final homeRaw = _asMap(json['homeTab']) ?? _asMap(json['home']);
    final home = homeRaw == null
        ? fallback.homeTab
        : LauncherContentPage.fromJson(
            homeRaw,
            fallback: fallback.homeTab,
            defaultId: 'home',
            defaultLabel: fallback.homeTab.label,
            defaultIcon: fallback.homeTab.icon,
            defaultTitle: fallback.homeTab.title,
            defaultGreetingEnabled: fallback.homeTab.greetingEnabled,
          );

    final tabs = <LauncherContentPage>[];
    final seenIds = <String>{home.id.toLowerCase()};
    final tabsRaw = json['tabs'];
    if (tabsRaw is List) {
      for (var i = 0; i < tabsRaw.length; i++) {
        final raw = _asMap(tabsRaw[i]);
        if (raw == null) continue;
        final parsed = LauncherContentPage.fromJson(
          raw,
          defaultId: 'tab-${i + 1}',
          defaultLabel: 'Tab ${i + 1}',
          defaultIcon: 'web_rounded',
          defaultTitle: 'Tab ${i + 1}',
          defaultGreetingEnabled: false,
        );
        final normalizedId = parsed.id.toLowerCase();
        if (seenIds.contains(normalizedId)) continue;
        seenIds.add(normalizedId);
        tabs.add(parsed);
      }
    }

    return LauncherContentConfig(homeTab: home, tabs: tabs);
  }

  static LauncherContentConfig defaults({
    required String repositoryUrl,
    required String discordInviteUrl,
  }) {
    return LauncherContentConfig(
      homeTab: LauncherContentPage(
        id: 'home',
        label: 'Home',
        icon: 'home_outlined',
        title: 'Home',
        greetingEnabled: true,
        heroRotationSeconds: 5,
        slides: <LauncherContentSlide>[
          LauncherContentSlide(
            image: 'assets/images/atlas_banner_v2.png',
            category: 'LAUNCHER',
            title: 'ATLAS',
            description:
                'ATLAS is the new era of OGFN. Built with a clean UI and user experience. Enjoy your stay.',
            buttonLabel: 'Open ATLAS Link GitHub',
            buttonUrl: repositoryUrl,
            imageFit: BoxFit.cover,
          ),
          LauncherContentSlide(
            image: 'assets/images/discord.webp',
            category: 'COMMUNITY',
            title: 'ATLAS Discord',
            description:
                'Join the ATLAS discord for more resources, news and updates!',
            buttonLabel: 'Join ATLAS Discord',
            buttonUrl: discordInviteUrl,
            imageFit: BoxFit.cover,
          ),
          LauncherContentSlide(
            image: 'assets/images/atlas_apps.png',
            category: 'SPOTLIGHT SUBMISSION',
            title: 'ATLAS Tutorial',
            description:
                'Watch this YouTube tutorial to learn how to use ATLAS, made by Mineluke (@mineluke)!',
            buttonLabel: 'Watch Video',
            buttonUrl: 'https://www.youtube.com/watch?v=C3pRAjzELzI',
            imageFit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}

class LauncherContentPage {
  const LauncherContentPage({
    required this.id,
    required this.label,
    required this.icon,
    required this.title,
    this.greetingEnabled = false,
    this.heroRotationSeconds = 5,
    this.slides = const <LauncherContentSlide>[],
    this.cards = const <LauncherContentCard>[],
  });

  final String id;
  final String label;
  final String icon;
  final String title;
  final bool greetingEnabled;
  final int heroRotationSeconds;
  final List<LauncherContentSlide> slides;
  final List<LauncherContentCard> cards;

  factory LauncherContentPage.fromJson(
    Map<String, dynamic> json, {
    LauncherContentPage? fallback,
    required String defaultId,
    required String defaultLabel,
    required String defaultIcon,
    required String defaultTitle,
    required bool defaultGreetingEnabled,
  }) {
    final slides = <LauncherContentSlide>[];
    final slidesRaw = json['slides'] ?? json['heroSlides'];
    if (slidesRaw is List) {
      for (final item in slidesRaw) {
        final raw = _asMap(item);
        if (raw == null) continue;
        slides.add(LauncherContentSlide.fromJson(raw));
      }
    }

    final cards = <LauncherContentCard>[];
    final cardsRaw = json['cards'] ?? json['linkCards'];
    if (cardsRaw is List) {
      for (final item in cardsRaw) {
        final raw = _asMap(item);
        if (raw == null) continue;
        cards.add(LauncherContentCard.fromJson(raw));
      }
    }

    final resolvedId = _sanitizeId(
      _asString(json['id'], defaultId),
      fallback: defaultId,
    );
    final resolvedLabel = _asString(json['label'], defaultLabel);
    final resolvedTitle = _asString(
      json['title'] ?? json['headerTitle'],
      resolvedLabel.isEmpty ? defaultTitle : resolvedLabel,
    );
    final resolvedSlides = slides.isNotEmpty
        ? slides
        : fallback?.slides ?? const <LauncherContentSlide>[];
    final resolvedCards = cards.isNotEmpty
        ? cards
        : fallback?.cards ?? const <LauncherContentCard>[];

    return LauncherContentPage(
      id: resolvedId,
      label: resolvedLabel.isEmpty ? defaultLabel : resolvedLabel,
      icon: _asString(json['icon'], defaultIcon),
      title: resolvedTitle.isEmpty ? defaultTitle : resolvedTitle,
      greetingEnabled: _asBool(
        json['greetingEnabled'],
        fallback?.greetingEnabled ?? defaultGreetingEnabled,
      ),
      heroRotationSeconds: _asInt(
        json['heroRotationSeconds'],
        fallback?.heroRotationSeconds ?? 5,
      ).clamp(0, 60),
      slides: resolvedSlides,
      cards: resolvedCards,
    );
  }
}

class LauncherContentSlide {
  const LauncherContentSlide({
    required this.image,
    required this.category,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonUrl,
    this.imageFit = BoxFit.contain,
  });

  final String image;
  final String category;
  final String title;
  final String description;
  final String buttonLabel;
  final String buttonUrl;
  final BoxFit imageFit;

  bool get hasButton =>
      buttonLabel.trim().isNotEmpty && buttonUrl.trim().isNotEmpty;

  factory LauncherContentSlide.fromJson(Map<String, dynamic> json) {
    return LauncherContentSlide(
      image: _asString(json['image'], ''),
      category: _asString(json['category'], ''),
      title: _asString(json['title'], 'ATLAS'),
      description: _asString(json['description'], ''),
      buttonLabel: _asString(json['buttonLabel'], ''),
      buttonUrl: _asString(json['buttonUrl'], ''),
      imageFit: _parseBoxFit(_asString(json['imageFit'], 'contain')),
    );
  }
}

class LauncherContentCard {
  const LauncherContentCard({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.buttonUrl,
    this.category = '',
    this.image = '',
    this.imageFit = BoxFit.cover,
  });

  final String title;
  final String description;
  final String buttonLabel;
  final String buttonUrl;
  final String category;
  final String image;
  final BoxFit imageFit;

  bool get hasButton =>
      buttonLabel.trim().isNotEmpty && buttonUrl.trim().isNotEmpty;

  bool get hasImage => image.trim().isNotEmpty;

  factory LauncherContentCard.fromJson(Map<String, dynamic> json) {
    return LauncherContentCard(
      title: _asString(json['title'], 'ATLAS'),
      description: _asString(json['description'], ''),
      buttonLabel: _asString(json['buttonLabel'], ''),
      buttonUrl: _asString(json['buttonUrl'], ''),
      category: _asString(json['category'], ''),
      image: _asString(json['image'], ''),
      imageFit: _parseBoxFit(_asString(json['imageFit'], 'cover')),
    );
  }
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

String _asString(dynamic value, String fallback) {
  final resolved = (value ?? fallback).toString().trim();
  return resolved.isEmpty ? fallback : resolved;
}

bool _asBool(dynamic value, bool fallback) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return fallback;
}

int _asInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

String _sanitizeId(String value, {required String fallback}) {
  final cleaned = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}

BoxFit _parseBoxFit(String value) {
  switch (value.trim().toLowerCase()) {
    case 'cover':
      return BoxFit.cover;
    case 'fill':
      return BoxFit.fill;
    case 'fitwidth':
    case 'fit_width':
      return BoxFit.fitWidth;
    case 'fitheight':
    case 'fit_height':
      return BoxFit.fitHeight;
    case 'none':
      return BoxFit.none;
    case 'scaledown':
    case 'scale_down':
      return BoxFit.scaleDown;
    default:
      return BoxFit.contain;
  }
}
