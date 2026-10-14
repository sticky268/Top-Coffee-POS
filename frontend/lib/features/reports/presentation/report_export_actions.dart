import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/reports_models.dart';
import '../data/report_exporter.dart';

class ReportExportActions extends StatefulWidget {
  const ReportExportActions({super.key, required this.report, required this.branch});
  final ReportsData report;
  final String branch;
  @override
  State<ReportExportActions> createState() => _ReportExportActionsState();
}

class _ReportExportActionsState extends State<ReportExportActions> {
  bool _busy = false;

  Future<void> _export(ReportExportFormat format) async {
    if (_busy) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final file = await ReportExporter.build(widget.report, widget.branch, format);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.name)],
        fileNameOverrides: [file.name],
        subject: 'Top Coffee POS sales report',
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not export this report. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8, runSpacing: 8,
    children: [
      for (final format in ReportExportFormat.values)
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _export(format),
          icon: const Icon(Icons.download_outlined),
          label: Text(format == ReportExportFormat.xlsx ? 'Excel' : format.name.toUpperCase()),
        ),
      if (_busy) const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
      ),
    ],
  );
}
