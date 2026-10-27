import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../common/formatter/id_formatter.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'brand.dart';
import 'home_view.dart';

/// Pushed by the portal with every heartbeat (app/src/lib/engine/policy.ts SUPPORT_PHONE_OPTION),
/// so admins change the numbers without a new release.
const kDolphinSupportPhoneOption = 'dolphin-support-phone';

/// Customer build's main window: the server model's ID and status into DolphinHomeView.
class DolphinHome extends StatelessWidget {
  const DolphinHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        // serverId is declared as a TextEditingController but built as the ID controller (server_model.dart).
        final id = trimID(model.serverId.text);
        return DolphinHomeView(
          id: id,
          state: serverStateFromStatus(model.connectStatus),
          phone: supportPhone(bind.mainGetOptionSync(key: kDolphinSupportPhoneOption), DolphinBrand.supportPhone),
          siteLabel: DolphinBrand.siteLabel,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: id));
            showToast('کپی شد');
          },
        );
      }),
    );
  }
}
