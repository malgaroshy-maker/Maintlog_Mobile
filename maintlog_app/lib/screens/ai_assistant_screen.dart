import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart'; // We'll add this dependency in a sec or deduce manually
import '../database/local_database.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final List<Map<String, dynamic>> _apiHistory = [];
  bool _isLoading = false;
  String? _apiKey;
  String _modelId = 'gemini-2.0-flash';
  PlatformFile? _selectedFile;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('gemini_api_key');
      _modelId = prefs.getString('gemini_model') ?? 'gemini-2.0-flash';
    });
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMessages = prefs.getString('chat_messages');
    final savedHistory = prefs.getString('chat_api_history');
    if (savedMessages != null) {
      final list = json.decode(savedMessages) as List;
      setState(() {
        _messages.clear();
        for (var m in list) {
          _messages.add(_ChatMessage(text: m['text'], isUser: m['isUser']));
        }
      });
    }
    if (savedHistory != null) {
      _apiHistory.clear();
      final list = json.decode(savedHistory) as List;
      for (var item in list) {
        _apiHistory.add(Map<String, dynamic>.from(item));
      }
    }
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final msgs = _messages
        .map((m) => {'text': m.text, 'isUser': m.isUser})
        .toList();
    await prefs.setString('chat_messages', json.encode(msgs));
    await prefs.setString('chat_api_history', json.encode(_apiHistory));
  }

  String get _systemPrompt =>
      'You are MaintLog AI, an intelligent assistant for MaintLog Pro — a factory maintenance logbook app. '
          'Today is ' +
      DateTime.now().toIso8601String().split('T')[0] +
      '. '
          'The available shifts are: Morning Shift, Evening Shift, Night Shift.\n\n'
          'CRITICAL RULES:\n'
          '1. ALWAYS call get_all_reference_data FIRST before creating or editing entries. This gives you all valid machines (already formatted with their Line), engineers, lines, and spare parts (with stock levels) in one call.\n'
          '2. When creating entries, you MUST fill ALL fields: machine_id (from DB, MUST perfectly match the "Machine Name (Line Name)" format provided by get_all_reference_data), date, shift, work_description, total_time (realistic minutes like 15-120), line_id (from DB), engineers (comma-separated names from DB), parts_used (format: "PartName (Qty: N)"), and notes. Every entry MUST have a line, engineers, and spare parts assigned. If the work description involves replacing or using parts (bearings, seals, belts, filters, etc.), you MUST include the matching spare part from the database in parts_used with a realistic quantity.\n'
          '3. When asked to add random/sample entries, call get_all_reference_data, then create entries using real machine names (including the line in parenthesis), real engineer names, real line names, real spare parts from the DB, and realistic maintenance descriptions. ALWAYS include parts_used with quantity for every entry that involves physical work. Example: work_description="Replaced conveyor belt bearings", parts_used="Bearing Kit (Qty: 2)".\n'
          '4. To delete entries by date or criteria, use delete_entries_by_filter. Do NOT ask the user for IDs — the tool handles filtering internally.\n'
          '5. To edit an entry, call query_entries to find it, then call edit_entry with the ID and updated fields.\n'
          '6. Be proactive — use your tools immediately instead of asking the user for details you can look up.\n'
          '7. Be concise. After tool calls, summarize what you did (e.g. "Created 3 entries" or "Deleted 5 entries from today").';

  List<Map<String, dynamic>> get _toolDeclarations => [
    {
      'functionDeclarations': [
        {
          'name': 'get_all_reference_data',
          'description':
              'Get all valid machines, engineers, lines, and spare parts from the database in one call. ALWAYS call this FIRST before creating or editing entries.',
          'parameters': {'type': 'OBJECT', 'properties': {}},
        },
        {
          'name': 'query_entries',
          'description':
              'Search log entries with optional filters. Use this to find entries before editing or deleting them.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'date': {
                'type': 'STRING',
                'description': 'Filter by date (YYYY-MM-DD)',
              },
              'shift': {
                'type': 'STRING',
                'description': 'Filter by shift name',
              },
              'machine_id': {
                'type': 'STRING',
                'description': 'Filter by machine name',
              },
            },
          },
        },
        {
          'name': 'get_dashboard_stats',
          'description':
              'Get KPI statistics: total entries today, total downtime, pending tasks.',
          'parameters': {'type': 'OBJECT', 'properties': {}},
        },
        {
          'name': 'create_entries',
          'description':
              'Create one or more log entries. Use for both single and batch creation. Always use valid machine names from query_database.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'entries': {
                'type': 'ARRAY',
                'description': 'Array of entries to create',
                'items': {
                  'type': 'OBJECT',
                  'properties': {
                    'machine_id': {
                      'type': 'STRING',
                      'description':
                          'Machine name strictly from get_all_reference_data (e.g. "CFA (Line 1)")',
                    },
                    'date': {
                      'type': 'STRING',
                      'description': 'Date in YYYY-MM-DD format',
                    },
                    'shift': {
                      'type': 'STRING',
                      'description':
                          'Morning Shift, Evening Shift, or Night Shift',
                    },
                    'work_description': {
                      'type': 'STRING',
                      'description':
                          'Description of maintenance work performed',
                    },
                    'total_time': {
                      'type': 'INTEGER',
                      'description': 'Time spent in minutes',
                    },
                    'line_id': {
                      'type': 'STRING',
                      'description': 'Line name (must exist in database)',
                    },
                    'engineers': {
                      'type': 'STRING',
                      'description':
                          'Comma-separated engineer names (must exist in database)',
                    },
                    'parts_used': {
                      'type': 'STRING',
                      'description':
                          'Spare parts used, e.g. "Seal Kit (Qty: 2)"',
                    },
                    'notes': {
                      'type': 'STRING',
                      'description': 'Additional notes',
                    },
                  },
                  'required': [
                    'machine_id',
                    'date',
                    'shift',
                    'work_description',
                  ],
                },
              },
            },
            'required': ['entries'],
          },
        },
        {
          'name': 'edit_entry',
          'description':
              'Edit an existing log entry. Only provide fields that need to be updated.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'id': {'type': 'STRING', 'description': 'The entry ID to edit'},
              'machine_id': {
                'type': 'STRING',
                'description': 'Updated machine name',
              },
              'date': {
                'type': 'STRING',
                'description': 'Updated date (YYYY-MM-DD)',
              },
              'shift': {'type': 'STRING', 'description': 'Updated shift'},
              'work_description': {
                'type': 'STRING',
                'description': 'Updated work description',
              },
              'total_time': {
                'type': 'INTEGER',
                'description': 'Updated time in minutes',
              },
              'line_id': {'type': 'STRING', 'description': 'Updated line name'},
              'engineers': {
                'type': 'STRING',
                'description': 'Updated engineers',
              },
              'parts_used': {
                'type': 'STRING',
                'description': 'Updated spare parts',
              },
              'notes': {'type': 'STRING', 'description': 'Updated notes'},
            },
            'required': ['id'],
          },
        },
        {
          'name': 'delete_entries',
          'description':
              'Delete one or more log entries by their IDs. Use query_entries first to find the IDs.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'ids': {
                'type': 'ARRAY',
                'description': 'Array of entry IDs to delete',
                'items': {'type': 'STRING'},
              },
            },
            'required': ['ids'],
          },
        },
        {
          'name': 'delete_entries_by_filter',
          'description':
              'Delete ALL log entries matching the given filters. Handles querying and deletion internally - no need to find IDs first.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'date': {
                'type': 'STRING',
                'description': 'Delete entries on this date (YYYY-MM-DD)',
              },
              'shift': {
                'type': 'STRING',
                'description': 'Only delete entries from this shift',
              },
              'machine_id': {
                'type': 'STRING',
                'description': 'Only delete entries for this machine',
              },
            },
          },
        },
      ],
    },
  ];

  Future<Map<String, dynamic>> _executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    final db = LocalDatabase.instance;

    switch (name) {
      case 'get_all_reference_data':
        final database = await db.database;
        final machines = await database.query('machines');
        final engineers = await database.query('engineers');
        final lines = await database.query('line_numbers');
        final parts = await database.query('spare_parts');

        // Format machines explicitly tied to their lines
        final formattedMachines = <String>[];
        for (var m in machines) {
          final lineId = m['line_id']?.toString();
          String lineName = 'Unassigned';
          if (lineId != null) {
            final line = lines.where((l) => l['id'] == lineId).firstOrNull;
            if (line != null) lineName = line['name'].toString();
          }
          formattedMachines.add('${m['name']} ($lineName)');
        }

        return {
          'machines': formattedMachines,
          'engineers': engineers.map((e) => e['full_name']).toList(),
          'lines': lines.map((l) => l['name']).toList(),
          'spare_parts': parts
              .map((p) => {'name': p['name'], 'stock': p['stock']})
              .toList(),
        };

      case 'query_entries':
        final database = await db.database;
        String where = '1=1';
        List<dynamic> whereArgs = [];
        if (args['date'] != null) {
          where += ' AND date = ?';
          whereArgs.add(args['date']);
        }
        if (args['shift'] != null) {
          where += ' AND shift = ?';
          whereArgs.add(args['shift']);
        }
        if (args['machine_id'] != null) {
          where += ' AND machine_id = ?';
          whereArgs.add(args['machine_id']);
        }
        final entries = await database.query(
          'log_entries',
          where: where,
          whereArgs: whereArgs,
          orderBy: 'date DESC, created_at DESC',
          limit: 50,
        );
        return {'entries': entries, 'count': entries.length};

      case 'get_dashboard_stats':
        final todayEntries = await db.getTodayEntries();
        final pendingTasks = await db.getPendingTaskCount();
        int totalDowntime = 0;
        for (var e in todayEntries) {
          totalDowntime += (e['total_time'] as int? ?? 0);
        }
        return {
          'today_entries': todayEntries.length,
          'total_downtime_minutes': totalDowntime,
          'pending_tasks': pendingTasks,
        };

      case 'create_entries':
        final entries = args['entries'] as List? ?? [];
        int count = 0;
        final createdIds = <String>[];
        for (var e in entries) {
          final id =
              'entry_' +
              DateTime.now().millisecondsSinceEpoch.toString() +
              '_' +
              count.toString();
          final entry = {
            'id': id,
            'machine_id': e['machine_id'] ?? '',
            'date': e['date'] ?? DateTime.now().toIso8601String().split('T')[0],
            'shift': e['shift'] ?? 'Morning Shift',
            'work_description': e['work_description'] ?? '',
            'total_time': e['total_time'] is int
                ? e['total_time']
                : int.tryParse(e['total_time']?.toString() ?? '0') ?? 0,
            'line_id': e['line_id'],
            'engineers': e['engineers'],
            'parts_used': e['parts_used'],
            'notes': e['notes'] ?? '',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            'sync_status': 'pending',
          };
          await db.insertEntry(entry);
          createdIds.add(id);
          count++;
          // Small delay to ensure unique timestamps
          await Future.delayed(const Duration(milliseconds: 2));
        }
        return {
          'success': true,
          'count': count,
          'ids': createdIds,
          'message': '$count entries created successfully',
        };

      case 'edit_entry':
        final id = args['id'] as String?;
        if (id == null)
          return {'success': false, 'message': 'No entry ID provided'};

        final database = await db.database;
        final existing = await database.query(
          'log_entries',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (existing.isEmpty)
          return {'success': false, 'message': 'Entry not found'};

        final updates = Map<String, dynamic>.from(existing.first);
        if (args['machine_id'] != null)
          updates['machine_id'] = args['machine_id'];
        if (args['date'] != null) updates['date'] = args['date'];
        if (args['shift'] != null) updates['shift'] = args['shift'];
        if (args['work_description'] != null)
          updates['work_description'] = args['work_description'];
        if (args['total_time'] != null)
          updates['total_time'] = args['total_time'] is int
              ? args['total_time']
              : int.tryParse(args['total_time']?.toString() ?? '0') ?? 0;
        if (args['line_id'] != null) updates['line_id'] = args['line_id'];
        if (args['engineers'] != null) updates['engineers'] = args['engineers'];
        if (args['parts_used'] != null)
          updates['parts_used'] = args['parts_used'];
        if (args['notes'] != null) updates['notes'] = args['notes'];
        updates['updated_at'] = DateTime.now().toIso8601String();
        updates['sync_status'] = 'pending';

        await database.update(
          'log_entries',
          updates,
          where: 'id = ?',
          whereArgs: [id],
        );
        return {'success': true, 'message': 'Entry updated'};

      case 'delete_entries':
        final ids = args['ids'] as List? ?? [];
        int deleted = 0;
        for (var id in ids) {
          await db.deleteEntry(id.toString());
          deleted++;
        }
        return {
          'success': true,
          'count': deleted,
          'message': '$deleted entries deleted',
        };

      case 'delete_entries_by_filter':
        final database2 = await db.database;
        String delWhere = '1=1';
        List<dynamic> delArgs = [];
        if (args['date'] != null) {
          delWhere += ' AND date = ?';
          delArgs.add(args['date']);
        }
        if (args['shift'] != null) {
          delWhere += ' AND shift = ?';
          delArgs.add(args['shift']);
        }
        if (args['machine_id'] != null) {
          delWhere += ' AND machine_id = ?';
          delArgs.add(args['machine_id']);
        }
        final toDelete = await database2.query(
          'log_entries',
          where: delWhere,
          whereArgs: delArgs,
        );
        int delCount = 0;
        for (var entry in toDelete) {
          await db.deleteEntry(entry['id'] as String);
          delCount++;
        }
        return {
          'success': true,
          'count': delCount,
          'message': '$delCount entries deleted',
          'deleted_ids': toDelete.map((e) => e['id']).toList(),
        };

      default:
        return {'error': 'Unknown function: $name'};
    }
  }

  Future<Map<String, dynamic>> _callGeminiApi(
    List<Map<String, dynamic>> contents,
  ) async {
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$_modelId:generateContent?key=$_apiKey';

    final body = {
      'contents': contents,
      'tools': _toolDeclarations,
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt},
        ],
      },
    };

    final client = HttpClient();
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(json.encode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    client.close();

    return json.decode(responseBody) as Map<String, dynamic>;
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _apiKey == null || _apiKey!.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final parts = <Map<String, dynamic>>[];
      if (text.trim().isNotEmpty) {
        parts.add({'text': text});
      }

      if (_selectedFile != null && _selectedFile!.bytes != null) {
        final mimeType =
            lookupMimeType(_selectedFile!.name) ?? 'application/octet-stream';
        parts.add({
          'inlineData': {
            'mimeType': mimeType,
            'data': base64Encode(_selectedFile!.bytes!),
          },
        });
      }

      _apiHistory.add({'role': 'user', 'parts': parts});

      setState(() {
        _selectedFile = null;
      });

      var apiResponse = await _callGeminiApi(_apiHistory);

      int maxRounds = 10; // Allow more rounds for multi-step operations
      while (maxRounds-- > 0) {
        if (apiResponse['error'] != null) {
          final errorMsg = apiResponse['error']['message'] ?? 'API error';
          throw Exception(errorMsg);
        }

        final candidates = apiResponse['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No response from model');
        }

        final content = candidates[0]['content'] as Map<String, dynamic>;
        final parts = content['parts'] as List;

        // Preserve full model response (including thought signatures)
        _apiHistory.add(content);

        final functionCalls = parts
            .where((p) => p['functionCall'] != null)
            .toList();
        if (functionCalls.isEmpty) {
          final textParts = parts.where((p) => p['text'] != null).toList();
          final replyText = textParts.isNotEmpty
              ? textParts.map((p) => p['text']).join('\n')
              : 'Done.';

          setState(() {
            _messages.add(_ChatMessage(text: replyText, isUser: false));
            _isLoading = false;
          });
          _saveChatHistory();
          break;
        }

        // Execute all function calls
        final functionResponseParts = <Map<String, dynamic>>[];
        for (var fc in functionCalls) {
          final call = fc['functionCall'];
          final name = call['name'] as String;
          final args = (call['args'] as Map<String, dynamic>?) ?? {};
          debugPrint('AI calling tool: $name with args: $args');
          final result = await _executeTool(name, args);
          functionResponseParts.add({
            'functionResponse': {'name': name, 'response': result},
          });
        }

        _apiHistory.add({'role': 'user', 'parts': functionResponseParts});
        apiResponse = await _callGeminiApi(_apiHistory);
      }
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(text: 'Error: $e', isUser: false));
        _isLoading = false;
      });
      _saveChatHistory();
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasApiKey = _apiKey != null && _apiKey!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Assistant'),
            Text(
              _modelId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear chat',
            onPressed: () async {
              setState(() {
                _messages.clear();
                _apiHistory.clear();
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('chat_messages');
              await prefs.remove('chat_api_history');
            },
          ),
        ],
      ),
      body: !hasApiKey
          ? _buildSetupPrompt()
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) =>
                              _buildBubble(_messages[index]),
                        ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Thinking...'),
                      ],
                    ),
                  ),
                _buildInputBar(),
              ],
            ),
    );
  }

  Widget _buildSetupPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'AI Assistant',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set up your Gemini API key in Settings to start.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.settings),
              label: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'MaintLog AI',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Try asking:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ..._buildSuggestions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSuggestions() {
    final suggestions = [
      'Add 3 random maintenance entries for today',
      'Show me all entries from today',
      'What machine had the most downtime?',
      'Delete all entries from today',
    ];
    return suggestions
        .map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _sendMessage(s),
              child: Text(
                s,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        )
        .toList();
  }

  Widget _buildBubble(_ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: msg.isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: msg.isUser ? const Radius.circular(4) : null,
            bottomLeft: !msg.isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: SelectableText(
          msg.text,
          style: TextStyle(
            color: msg.isUser ? Theme.of(context).colorScheme.onPrimary : null,
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_selectedFile != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedFile!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _selectedFile = null),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      hintText: 'Ask MaintLog AI...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _sendMessage(_inputController.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}
