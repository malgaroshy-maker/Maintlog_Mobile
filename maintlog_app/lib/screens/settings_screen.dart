import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import 'spare_parts_screen.dart';
import 'manage_machines_screen.dart';
import 'manage_engineers_screen.dart';
import 'manage_lines_screen.dart';
import 'user_approval_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Not logged in';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Administration')),
      body: ListView(
        children: [
          _buildSectionHeader(context, 'Preferences'),
          SwitchListTile(
            secondary: Icon(
              themeProvider.isDark ? Icons.dark_mode : Icons.light_mode,
            ),
            title: const Text('Dark Mode'),
            subtitle: Text(
              themeProvider.isDark ? 'Dark theme active' : 'Light theme active',
            ),
            value: themeProvider.isDark,
            onChanged: (_) => themeProvider.toggleTheme(),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            subtitle: const Text('English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguageDialog(context),
          ),

          _buildSectionHeader(context, 'AI Assistant'),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Gemini API Key'),
            subtitle: const Text('Tap to configure'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showApiKeyDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.model_training),
            title: const Text('AI Model'),
            subtitle: const Text('Tap to select model'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showModelSelector(context),
          ),

          _buildSectionHeader(context, 'Account'),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile Settings'),
            subtitle: Text(email),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showProfileDialog(context, email),
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About the App'),
            subtitle: const Text('Developer info & contact'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('stayLoggedIn', false);
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),

          _buildSectionHeader(context, 'Administration (Admin Only)'),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('Management Tools'),
            subtitle: const Text('Machines, Lines, Engineers, Parts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAdminModal(context),
          ),
          ListTile(
            leading: const Icon(Icons.how_to_reg),
            title: const Text('User Approval Dashboard'),
            subtitle: const Text('Approve or reject new sign-ups'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserApprovalScreen()),
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    final currentL = localeProvider.locale.languageCode;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Language / اختر اللغة'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              localeProvider.setLocale(const Locale('en'));
            },
            child: ListTile(
              leading: const Text('🇬🇧', style: TextStyle(fontSize: 24)),
              title: const Text('English'),
              trailing: currentL == 'en'
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              localeProvider.setLocale(const Locale('ar'));
            },
            child: ListTile(
              leading: const Text('🇸🇦', style: TextStyle(fontSize: 24)),
              title: const Text('العربية (Arabic)'),
              trailing: currentL == 'ar'
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context, String email) {
    final user = Supabase.instance.client.auth.currentUser;
    final createdAt = user?.createdAt ?? 'Unknown';
    final uid = user?.id ?? 'N/A';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profile Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _profileRow(Icons.email, 'Email', email),
            const SizedBox(height: 12),
            _profileRow(Icons.badge, 'User ID', uid.substring(0, 8) + '...'),
            const SizedBox(height: 12),
            _profileRow(
              Icons.calendar_today,
              'Account Created',
              createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              _showChangePasswordDialog(context);
            },
            icon: const Icon(Icons.lock),
            label: const Text('Change Password'),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newPassword = passwordController.text.trim();
              if (newPassword.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password must be at least 6 characters'),
                  ),
                );
                return;
              }
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(password: newPassword),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password updated successfully!'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ' + e.toString())),
                  );
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About MaintLog Pro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MaintLog Pro is a comprehensive maintenance logging and management application designed for industrial environments.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Developer Details',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _profileRow(Icons.person, 'Developer', 'Mahamed Algaroshy'),
            const SizedBox(height: 8),
            _profileRow(Icons.email, 'Contact Email', 'Malgaroshy@gmail.com'),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Version 1.0.0',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAdminModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Management Tools',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text('Spare Parts Inventory'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SparePartsScreen()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.precision_manufacturing),
                title: const Text('Machines & Equipment'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManageMachinesScreen(),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: const Text('Production Lines'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManageLinesScreen(),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.engineering),
                title: const Text('Engineering Crew'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManageEngineersScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showApiKeyDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentKey = prefs.getString('gemini_api_key') ?? '';
    final controller = TextEditingController(text: currentKey);

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API Key'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'API Key',
            border: OutlineInputBorder(),
            hintText: 'AIza...',
            prefixIcon: Icon(Icons.key),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await prefs.setString('gemini_api_key', controller.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('API Key saved!')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showModelSelector(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentModel = prefs.getString('gemini_model') ?? 'gemini-2.0-flash';
    final apiKey = prefs.getString('gemini_api_key') ?? '';

    if (apiKey.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please set your API key first')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch available models from Gemini API
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=' + apiKey,
      );
      final client = HttpClient();
      final request = await client.getUrl(url);
      final response = await request.close();
      final body = await response
          .transform(const SystemEncoding().decoder)
          .join();
      client.close();

      final data = json.decode(body) as Map<String, dynamic>;
      final modelList = (data['models'] as List? ?? [])
          .where((m) {
            final name = m['name'] as String? ?? '';
            final methods =
                (m['supportedGenerationMethods'] as List?)?.cast<String>() ??
                [];
            final isSupported = methods.contains('generateContent');
            final isGemini25 = name.contains('gemini-2.5');
            final isGemini3 = name.contains('gemini-3');
            return isSupported && (isGemini25 || isGemini3);
          })
          .map((m) {
            final name = (m['name'] as String).replaceFirst('models/', '');
            final displayName = m['displayName'] as String? ?? name;
            final desc = m['description'] as String? ?? '';
            return {'id': name, 'name': displayName, 'desc': desc};
          })
          .toList();

      if (!context.mounted) return;
      Navigator.pop(context); // remove loading

      if (modelList.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No models found for this API key')),
          );
        }
        return;
      }

      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select AI Model'),
          children: modelList
              .map(
                (m) => SimpleDialogOption(
                  onPressed: () async {
                    await prefs.setString('gemini_model', m['id']!);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Model set to ' + m['name']!)),
                      );
                    }
                  },
                  child: ListTile(
                    leading: Icon(
                      currentModel == m['id']
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: currentModel == m['id']
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      m['name']!,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      m['desc']!.length > 60
                          ? m['desc']!.substring(0, 60) + '...'
                          : m['desc']!,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // remove loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching models: ' + e.toString())),
        );
      }
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
