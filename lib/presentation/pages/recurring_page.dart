import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:expense_tracker/domain/entities/recurring_template.dart';
import 'package:expense_tracker/presentation/providers/providers.dart';

/// The rows that come back every month.
///
/// Templates are made where transactions are made — the switch at the bottom of
/// the add screen — so this page only reads, pauses and deletes them. Adding a
/// second form here would have meant two places that decide what a transaction
/// is, and two places to keep in step.
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecurringTemplateEntity>> templates =
        ref.watch(recurringTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: templates.when(
        data: (List<RecurringTemplateEntity> rows) =>
            rows.isEmpty ? const _EmptyState() : _TemplateList(templates: rows),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not read the recurring list: $error'),
          ),
        ),
      ),
    );
  }
}

class _TemplateList extends ConsumerWidget {
  final List<RecurringTemplateEntity> templates;

  const _TemplateList({required this.templates});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: templates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) {
        final RecurringTemplateEntity template = templates[index];
        final Color color =
            template.isIncome ? const Color(0xFF2E9E5B) : const Color(0xFFD64545);

        return Dismissible(
          key: ValueKey(template.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFD64545),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          // Asked here and answered `false` either way, as on the dashboard: the
          // delete goes through the stream that draws the list, so the list keeps
          // telling the truth instead of pre-empting the write.
          confirmDismiss: (_) async {
            await _confirmDelete(context, ref, template);
            return false;
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.repeat_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.displayCategory,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (template.note != null && template.note!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          template.note!,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        template.active
                            ? 'Every month on day ${template.dayOfMonth}'
                            : 'Paused — day ${template.dayOfMonth}',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${template.isIncome ? '+' : '-'}'
                  '${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(template.amount)}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                ),
                Switch(
                  value: template.active,
                  onChanged: (bool active) => ref
                      .read(setRecurringTemplateActiveUseCaseProvider)
                      .call(template.id, active),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    RecurringTemplateEntity template,
  ) async {
    final bool? answer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete this recurring transaction?'),
        content: Text(
          '${template.displayCategory} stays in your history, but no new row will be '
          'added for it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (answer != true) return;
    await ref.read(deleteRecurringTemplateUseCaseProvider).call(template.id);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.repeat_rounded, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Nothing repeats yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Turn on "Repeat monthly" while adding a transaction. From then on it is '
              'added once a month, on the day you chose.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
