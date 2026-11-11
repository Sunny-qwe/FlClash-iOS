import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network.dart';

const _localRoutes = ['127.0.0.0/8', '10.7.0.0/24', '::1/128'];

class LocalNetworkView extends ConsumerWidget {
  const LocalNetworkView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    return Scaffold(
      title: l.localNetworkSettings,
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          generateSection(
            items: [
              ConfigToggleItem(
                title: (l) => l.localNetworkProtection,
                selector: patchClashConfigProvider.select(
                  (state) => _localRoutes.every(
                    state.tun.routeExcludeAddress.contains,
                  ),
                ),
                onChanged: (ref, value) {
                  ref.read(patchClashConfigProvider.notifier).update((state) {
                    final routes = state.tun.routeExcludeAddress;
                    return state.copyWith.tun(
                      routeExcludeAddress: value
                          ? {...routes, ..._localRoutes}.toList()
                          : routes
                                .where((route) => !_localRoutes.contains(route))
                                .toList(),
                    );
                  });
                },
              ),
              const BypassPrivateRouteItem(),
              ConfigListEditItem(
                title: (l) => l.routeExcludeAddress,
                itemMaxLength: TextInputLimits.cidr,
                itemValidator: validateCidr,
                selector: patchClashConfigProvider.select(
                  (state) => state.tun.routeExcludeAddress,
                ),
                onChanged: (ref, value) => ref
                    .read(patchClashConfigProvider.notifier)
                    .update(
                      (state) => state.copyWith.tun(routeExcludeAddress: value),
                    ),
              ),
            ],
            footer: l.localNetworkProtectionDesc,
          ),
          generateSection(
            title: l.systemProxy,
            items: const [VpnSystemProxyItem(), BypassDomainItem()],
            footer: l.bypassDomainDesc,
          ),
          generateSection(
            title: l.network,
            items: const [Ipv6Item(), DNSHijackingItem(), TunStackItem()],
            footer: l.vpnConfigChangeDetected,
          ),
        ],
      ),
    );
  }
}
