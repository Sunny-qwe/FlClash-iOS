import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/ui/list_item.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _selectedIconPrefKey = 'selected_alternate_app_icon';

class AppIconOption {
  final String id;
  final String name;
  final String description;
  final String assetPath;

  const AppIconOption({
    required this.id,
    required this.name,
    required this.description,
    required this.assetPath,
  });
}

const appIconOptions = [
  AppIconOption(
    id: 'AppIcon-Classic',
    name: '经典原版 (Classic)',
    description: '官方经典蓝紫配色，极简清爽明亮',
    assetPath: 'assets/images/app_icons/AppIcon-Classic.png',
  ),
  AppIconOption(
    id: 'AppIcon-Dark',
    name: '黑曜暗金 (Obsidian Gold)',
    description: '深邃黑金微光质感，OLED 极客暗黑',
    assetPath: 'assets/images/app_icons/AppIcon-Dark.png',
  ),
  AppIconOption(
    id: 'AppIcon-Neon',
    name: '赛博霓虹 (Cyber Neon)',
    description: '幻彩极光与霓虹电波，赛博朋克风格',
    assetPath: 'assets/images/app_icons/AppIcon-Neon.png',
  ),
  AppIconOption(
    id: 'AppIcon-Sunset',
    name: '落日晚霞 (Sunset Orange)',
    description: '暮色珊瑚与炽烈晚霞，温暖明媚活力',
    assetPath: 'assets/images/app_icons/AppIcon-Sunset.png',
  ),
  AppIconOption(
    id: 'AppIcon-Emerald',
    name: '翡翠薄荷 (Emerald Mint)',
    description: '清新森林与微光绿意，通透护眼质感',
    assetPath: 'assets/images/app_icons/AppIcon-Emerald.png',
  ),
  AppIconOption(
    id: 'AppIcon-Sakura',
    name: '浪漫樱花 (Sakura Blossom)',
    description: '柔和春樱与轻盈花瓣，清新甜美梦幻',
    assetPath: 'assets/images/app_icons/AppIcon-Sakura.png',
  ),
  AppIconOption(
    id: 'AppIcon-Titanium',
    name: '钛合金灰 (Titanium Gray)',
    description: '苹果极简哑光金属，硬朗工业质感',
    assetPath: 'assets/images/app_icons/AppIcon-Titanium.png',
  ),
  AppIconOption(
    id: 'AppIcon-Purple',
    name: '极光幽紫 (Royal Violet)',
    description: '星河宇宙与神秘深紫，高贵优雅深邃',
    assetPath: 'assets/images/app_icons/AppIcon-Purple.png',
  ),
];

class AppIconView extends ConsumerStatefulWidget {
  const AppIconView({super.key});

  @override
  ConsumerState<AppIconView> createState() => _AppIconViewState();
}

class _AppIconViewState extends ConsumerState<AppIconView> {
  String _currentIconId = 'AppIcon-Classic';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentIcon();
  }

  Future<void> _loadCurrentIcon() async {
    String? current;
    if (system.isIOS) {
      try {
        current = await service?.getAlternateIconName();
      } catch (_) {}
    }
    if (current == null || current.isEmpty) {
      final sp = await SharedPreferences.getInstance();
      current = sp.getString(_selectedIconPrefKey);
    }
    setState(() {
      _currentIconId = current ?? 'AppIcon-Classic';
      _isLoading = false;
    });
  }

  Future<void> _switchIcon(AppIconOption option) async {
    if (_currentIconId == option.id) return;
    setState(() {
      _currentIconId = option.id;
    });

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_selectedIconPrefKey, option.id);

    if (system.isIOS) {
      try {
        final iconName = option.id == 'AppIcon-Classic' ? null : option.id;
        await service?.setAlternateIconName(iconName);
      } catch (e) {
        if (mounted) {
          dialogs.showBanner('切换图标失败: $e', level: BannerLevel.error);
          return;
        }
      }
    }

    if (mounted) {
      dialogs.showBanner(
        '已切换应用图标为【${option.name}】',
        level: BannerLevel.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: '应用图标',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '点击下方图标即可实时切换 iOS 主屏幕应用图标风格。',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...appIconOptions.map((opt) {
                  final isSelected = _currentIconId == opt.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                          : Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _switchIcon(opt),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 1.8,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(
                                    opt.assetPath,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        color: isSelected
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      opt.description,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isSelected)
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                )
                              else
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outlineVariant,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
