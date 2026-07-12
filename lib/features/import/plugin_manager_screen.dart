import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import 'plugins_provider.dart';

class PluginManagerScreen extends ConsumerStatefulWidget {
  const PluginManagerScreen({super.key});

  @override
  ConsumerState<PluginManagerScreen> createState() => _PluginManagerScreenState();
}

class _PluginManagerScreenState extends ConsumerState<PluginManagerScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _showAddPluginBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddPluginBottomSheet(
        nameController: _nameController,
        descController: _descController,
        urlController: _urlController,
        formKey: _formKey,
        onAdd: (name, desc, url) {
          ref.read(pluginsProvider.notifier).addCustomPlugin(
                name: name,
                description: desc,
                endpointUrl: url,
              );
          _nameController.clear();
          _descController.clear();
          _urlController.clear();
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully installed "$name" plugin! 🔌'),
              backgroundColor: AppColors.primary,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final plugins = ref.watch(pluginsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textPrimary),
        title: Text(
          'Plugin Manager',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            physics: const BouncingScrollPhysics(),
            children: [
              _buildHeaderCard(isDark),
              const SizedBox(height: 20),
              Text(
                'INSTALLED PLUGINS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.6) : AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              if (plugins.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('No plugins available.', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              else
                ...plugins.map((plugin) => _buildPluginCard(isDark, plugin)),
              const SizedBox(height: 80), // spacer for floating action button
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPluginBottomSheet(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Plugin'),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.primaryDark.withValues(alpha: 0.15), Colors.transparent]
              : [AppColors.green50.withValues(alpha: 0.5), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.extension_rounded, color: AppColors.primary, size: 36),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dynamic Importer Engine',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage and toggle platform plugins or install third-party URL scrapers to load external media links.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPluginCard(bool isDark, PluginManifest plugin) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder.withValues(alpha: 0.5) : AppColors.surfaceBorder.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: plugin.color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(plugin.icon, color: plugin.color, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                plugin.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            if (plugin.isCustom)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CUSTOM',
                  style: TextStyle(color: Colors.purple, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              plugin.description,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (plugin.configUrl != null) ...[
              const SizedBox(height: 6),
              Text(
                'Source: ${plugin.configUrl}',
                style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontFamily: 'monospace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: plugin.isEnabled,
              activeColor: AppColors.primary,
              onChanged: (_) {
                ref.read(pluginsProvider.notifier).togglePlugin(plugin.id);
              },
            ),
            if (plugin.isCustom)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                onPressed: () {
                  ref.read(pluginsProvider.notifier).removeCustomPlugin(plugin.id);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AddPluginBottomSheet extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController descController;
  final TextEditingController urlController;
  final GlobalKey<FormState> formKey;
  final void Function(String name, String desc, String url) onAdd;

  const _AddPluginBottomSheet({
    required this.nameController,
    required this.descController,
    required this.urlController,
    required this.formKey,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder, width: 1.5),
        ),
      ),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // drag handle
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Install Custom Importer Plugin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField(
                isDark: isDark,
                controller: nameController,
                label: 'Plugin Name',
                hint: 'e.g. My Custom Scraper',
                validator: (v) => v == null || v.isEmpty ? 'Plugin name is required' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                isDark: isDark,
                controller: descController,
                label: 'Description',
                hint: 'e.g. Scrapes custom platform video/audio links',
                validator: (v) => v == null || v.isEmpty ? 'Description is required' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                isDark: isDark,
                controller: urlController,
                label: 'Endpoint API URL',
                hint: 'https://api.my-plugin.com/extract',
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Endpoint URL is required';
                  if (!v.startsWith('http://') && !v.startsWith('https://')) return 'Must start with http:// or https://';
                  return null;
                },
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    onAdd(nameController.text.trim(), descController.text.trim(), urlController.text.trim());
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Install Plugin',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required bool isDark,
    required TextEditingController controller,
    required String label,
    required String hint,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.gray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
          ),
          child: TextFormField(
            controller: controller,
            validator: validator,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
