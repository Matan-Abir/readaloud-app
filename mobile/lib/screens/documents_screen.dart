import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import 'reader_screen.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late Future<List<DocumentInfo>> _docs = widget.api.listDocuments();
  bool _uploading = false;

  void _reload() => setState(() => _docs = widget.api.listDocuments());

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _upload() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _uploading = true);
    try {
      await widget.api.uploadDocument(file.name, bytes);
      _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(DocumentInfo d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${d.title}" and its Q&A history will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteDocument(d.id);
      _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _open(DocumentInfo d) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(api: widget.api, doc: d)),
    );
    _reload(); // progress may have changed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: widget.api.logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        icon: _uploading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.upload_file),
        label: Text(_uploading ? 'Uploading…' : 'Add PDF'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<DocumentInfo>>(
          future: _docs,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('${snap.error}', textAlign: TextAlign.center),
                ),
                Center(child: TextButton(onPressed: _reload, child: const Text('Retry'))),
              ]);
            }
            final docs = snap.data!;
            if (docs.isEmpty) {
              return ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(48),
                  child: Text('No documents yet.\nTap "Add PDF" to upload an article.',
                      textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = docs[i];
                return ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d.pageCount} pages · ${(d.progress * 100).round()}% listened'),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: d.progress),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(d),
                  ),
                  onTap: () => _open(d),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
