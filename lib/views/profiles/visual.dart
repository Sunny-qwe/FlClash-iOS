import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'custom/custom.dart';
import 'custom/custom_proxies.dart';

class VisualConfigView extends ConsumerWidget {
  const VisualConfigView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    return Scaffold(
      title: l.visualConfig,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          generateSection(
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.addCircle),
                title: Text(l.addProfile),
                subtitle: Text(l.visualConfigDesc),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () {
                  final id = ref.read(profilesActionProvider.notifier)
                      .addCustomProfile(l.unnamed);
                  BaseNavigator.push(
                    context,
                    CustomProfileView(profileId: id, isNew: true),
                  );
                },
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.proxies),
                title: Text(l.proxies),
                subtitle: Text(l.visualNodeMembershipTip),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => BaseNavigator.push(context, const CustomProxiesView()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
