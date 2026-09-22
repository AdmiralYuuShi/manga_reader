import 'package:flutter/material.dart';

import 'library_controller.dart';
import 'library_model.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.controller,
    required this.onAddFolder,
    required this.onOpenRoot,
    required this.onOpenPage,
  });

  final LibraryController controller;
  final VoidCallback onAddFolder;
  final ValueChanged<LibraryRoot> onOpenRoot;
  final void Function(LibraryRoot root, LibraryFolder chapter, String pageName)
  onOpenPage;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final Set<String> _collapsedRoots = {};
  final Set<String> _expandedFolders = {};

  List<_LibraryRow> _visibleRows(List<LibraryRoot> roots) {
    final rows = <_LibraryRow>[];
    void appendChildren(LibraryRoot root, LibraryFolder folder, int depth) {
      for (final page in folder.pages) {
        rows.add(_LibraryRow(root, folder, page, depth));
      }
      for (final child in folder.children) {
        rows.add(_LibraryRow(root, child, null, depth));
        if (_expandedFolders.contains('${root.id}:${child.relativePath}')) {
          appendChildren(root, child, depth + 1);
        }
      }
    }

    for (final root in roots) {
      rows.add(_LibraryRow(root, null, null, 0));
      if (!_collapsedRoots.contains(root.id) && root.snapshot != null) {
        appendChildren(root, root.snapshot!, 1);
      }
    }
    return rows;
  }

  Future<void> _remove(LibraryRoot root) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Library?'),
        content: Text(
          'Remove ${root.name} from the library list? Source images and saved translations stay on disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.remove(root.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _status(String label, LibraryStatus status) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (status) {
      LibraryStatus.unavailable => colors.error,
      LibraryStatus.edited => colors.primary,
      LibraryStatus.partial => colors.tertiary,
      _ => colors.onSurfaceVariant,
    };
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    );
  }

  Widget _row(_LibraryRow row) {
    final root = row.root;
    final folder = row.folder;
    final page = row.page;
    final indent = (row.depth * 18.0).clamp(0.0, 72.0);
    if (folder == null) {
      final expanded = !_collapsedRoots.contains(root.id);
      return Tooltip(
        message: root.path,
        child: ListTile(
          key: ValueKey('library-root-${root.id}'),
          contentPadding: EdgeInsets.only(left: 12 + indent, right: 4),
          leading: Icon(expanded ? Icons.folder_open : Icons.folder),
          title: Text(root.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: _status(
            '${libraryStatusLabel(root.status)} · ${root.indexedAt == null ? 'Not indexed' : 'Last indexed ${root.indexedAt!.toLocal().toString().split('.').first}'}',
            root.status,
          ),
          onTap: () => setState(() {
            if (expanded) {
              _collapsedRoots.add(root.id);
            } else {
              _collapsedRoots.remove(root.id);
            }
          }),
          trailing: PopupMenuButton<String>(
            tooltip: 'Actions for ${root.name}',
            onSelected: (action) {
              if (action == 'open') widget.onOpenRoot(root);
              if (action == 'refresh') widget.controller.refresh(root.id);
              if (action == 'remove') _remove(root);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'open',
                enabled: root.available,
                child: const Text('Open in Reader'),
              ),
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove from Library'),
              ),
            ],
          ),
        ),
      );
    }
    if (page != null) {
      return Tooltip(
        message: '${folder.relativePath}/${page.name}',
        child: ListTile(
          key: ValueKey(
            'library-page-${root.id}-${folder.relativePath}-${page.name}',
          ),
          dense: true,
          contentPadding: EdgeInsets.only(left: 12 + indent, right: 8),
          leading: const Icon(Icons.image_outlined, size: 18),
          title: Text(page.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(libraryPageStatusLabel(page.status)),
          onTap: root.available
              ? () => widget.onOpenPage(root, folder, page.name)
              : null,
        ),
      );
    }
    final key = '${root.id}:${folder.relativePath}';
    final expanded = _expandedFolders.contains(key);
    final hasChildren = folder.children.isNotEmpty || folder.pages.isNotEmpty;
    return Tooltip(
      message: folder.relativePath,
      child: ListTile(
        key: ValueKey('library-folder-$key'),
        dense: true,
        contentPadding: EdgeInsets.only(left: 12 + indent, right: 4),
        leading: Icon(
          expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
          size: 18,
        ),
        title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: _status(
          libraryStatusLabel(folder.counts.status),
          folder.counts.status,
        ),
        onTap: hasChildren
            ? () => setState(() {
                if (expanded) {
                  _expandedFolders.remove(key);
                } else {
                  _expandedFolders.add(key);
                }
              })
            : null,
        trailing: folder.pages.isNotEmpty && root.available
            ? IconButton(
                tooltip: 'Open ${folder.name} in Reader',
                onPressed: () =>
                    widget.onOpenPage(root, folder, folder.pages.first.name),
                icon: const Icon(Icons.open_in_new, size: 18),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final roots = widget.controller.roots;
      final rows = _visibleRows(roots);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Translation Library',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: widget.onAddFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add / Open Folder'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: roots.isEmpty
                      ? null
                      : widget.controller.refreshAll,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Library',
                ),
              ],
            ),
          ),
          if (widget.controller.warning case final warning?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  warning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: roots.isEmpty
                ? Center(
                    child: Text(
                      widget.controller.loaded
                          ? 'Open a manga folder to add it to your library.'
                          : 'Loading library...',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('library-tree'),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _row(rows[index]),
                  ),
          ),
        ],
      );
    },
  );
}

class _LibraryRow {
  const _LibraryRow(this.root, this.folder, this.page, this.depth);
  final LibraryRoot root;
  final LibraryFolder? folder;
  final LibraryPage? page;
  final int depth;
}
