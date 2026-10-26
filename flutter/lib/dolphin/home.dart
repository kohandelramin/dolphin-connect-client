import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../models/server_model.dart';
import 'brand.dart';
import 'home_view.dart';

/// Customer build's main window: the server model's ID and status into DolphinHomeView.
class DolphinHome extends StatelessWidget {
  const DolphinHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, _) => DolphinHomeView(
          id: model.serverId.id,
          state: serverStateFromStatus(model.connectStatus),
          phone: DolphinBrand.supportPhone,
          siteLabel: DolphinBrand.siteLabel,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: model.serverId.id));
            showToast('کپی شد');
          },
        ),
      ),
    );
  }
}
