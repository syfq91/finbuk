import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

class EpubTocSheet extends StatelessWidget {
  final List<Link> toc;
  final void Function(Link) onTap;

  const EpubTocSheet({super.key, required this.toc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.list_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Table of Contents',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                children: toc
                    .map((link) => _buildItem(context, link, 0))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, Link link, int depth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 20.0 + depth * 16.0, right: 16),
          title: Text(
            link.title ?? 'Untitled',
            style: TextStyle(
              fontSize: depth == 0 ? 15 : 13,
              fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.normal,
              color: depth == 0
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurface.withAlpha(178),
            ),
          ),
          onTap: () => onTap(link),
        ),
        ...link.children.map((child) => _buildItem(context, child, depth + 1)),
      ],
    );
  }
}
