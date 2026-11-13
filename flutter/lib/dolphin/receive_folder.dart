import 'package:flutter/material.dart';

import 'theme.dart';

/// DD-12: where files the technician sends land by default, «دریافتی دلفین» under the customer's Downloads
/// (src/dolphin_system_core.rs `receive_dir`). `main_get_common("dolphin-receive-dir")` gives the path, or "" when the
/// portal's `receive-folder` switch hides it (upstream: the home folder). The technician's file manager opens there
/// and shows the path in its own address bar; this strip is for the customer's side.
const kDolphinReceiveDirKey = 'dolphin-receive-dir';
const kReceiveFolderName = 'دریافتی دلفین';
const kReceiveFolderLabel = 'فایل‌هایی که کارشناس می‌فرستد اینجا ذخیره می‌شوند:';

bool receiveFolderShown(String path) => path.trim().isNotEmpty;

/// The strip: the label and the path (left to right, so a Windows path reads in order), selectable for copying.
class DolphinReceiveFolderView extends StatelessWidget {
  final String path;
  const DolphinReceiveFolderView({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    if (!receiveFolderShown(path)) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: const ValueKey('dolphin-receive-folder'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: DolphinColors.azureSoft,
          borderRadius: BorderRadius.circular(DolphinRadii.control),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.folder_open, color: DolphinColors.azureText, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kReceiveFolderLabel, style: TextStyle(color: DolphinColors.ink, fontSize: 12)),
              const SizedBox(height: 2),
              SelectableText(path,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: DolphinColors.muted, fontSize: 11.5, height: 1.4)),
            ]),
          ),
        ]),
      ),
    );
  }
}
