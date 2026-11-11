import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
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
  bool _isSwitching = false;

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
        current ??= 'AppIcon-Classic';
      } catch (_) {}
    }
    if (current == null || current.isEmpty) {
      final sp = await SharedPreferences.getInstance();
      current = sp.getString(_selectedIconPrefKey);
    }
    if (mounted) {
      setState(() {
        _currentIconId = current ?? 'AppIcon-Classic';
        _isLoading = false;
      });
    }
  }

  Future<void> _switchIcon(AppIconOption option) async {
    if (_isSwitching || _currentIconId == option.id) return;
    _isSwitching = true;
    try {
      if (system.isIOS) {
        final iconName = option.id == 'AppIcon-Classic' ? null : option.id;
        final changed = await service?.setAlternateIconName(iconName) ?? false;
        if (!changed) {
          throw const MessageException('系统未确认图标切换成功');
        }
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_selectedIconPrefKey, option.id);
      if (!mounted) return;
      setState(() => _currentIconId = option.id);
      dialogs.showBanner(
        '已切换应用图标为【${option.name}】',
        level: BannerLevel.success,
      );
    } catch (error) {
      if (!mounted) return;
      final denied =
          error is PlatformException &&
          error.details is Map &&
          (error.details as Map)['domain'] == 'NSOSStatusErrorDomain' &&
          (error.details as Map)['code'] == -54;
      final message = denied
          ? context.appLocalizations.appIconAccessDenied
          : error is PlatformException
          ? error.message
          : error.toString();
      dialogs.showBanner('切换图标失败: $message', level: BannerLevel.error);
    } finally {
      _isSwitching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return BaseScaffold(
      title: '应用图标',
      body: _isLoading
          ? const Center(child: SizedBox(width: 32, height: 32))
          : ListView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: context.appBarInset + 12,
                bottom: 32 + context.bottomInset,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      GlyphIcon(
                        AppGlyphs.palette,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '点击下方图标即可实时切换 iOS 主屏幕应用图标风格。',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
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
                    child: GestureDetector(
                      onTap: () => _switchIcon(opt),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primaryContainer.withValues(
                                  alpha: 0.35,
                                )
                              : colorScheme.surfaceContainer,
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary
                                : const Color(0x00000000),
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
                                    color: const Color(0x1F000000),
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
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    opt.description,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colorScheme.onSurfaceVariant,
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
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: GlyphIcon(
                                    AppGlyphs.check,
                                    color: Color(0xFFFFFFFF),
                                    size: 16,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.outlineVariant,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                          ],
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
