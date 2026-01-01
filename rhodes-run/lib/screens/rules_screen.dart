import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rule.dart';
import '../services/health_service.dart';

// AppColors for rules screen
class AppColors {
  static const bg = Color(0xFF0d0d08);
  static const panel = Color(0xFF1a1a12);
  static const metal = Color(0xFF2a2a1c);
  static const amber = Color(0xFFffcc00);
  static const amberDim = Color(0xFFcc9900);
  static const green = Color(0xFF44ff44);
  static const greenDim = Color(0xFF22aa22);
  static const red = Color(0xFFff5555);
  static const redDim = Color(0xFFcc3333);
  static const text = Color(0xFFf0e8d0);
  static const textDim = Color(0xFFb0a080);
}

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  List<Rule> _rules = [];
  Progress _progress = Progress(stepsToday: 0, workoutMinutesToday: 0);
  final HealthService _health = HealthService.instance;
  StreamSubscription<int>? _stepsSubscription;

  @override
  void initState() {
    super.initState();
    _loadRules();
    _initHealthTracking();
  }

  Future<void> _initHealthTracking() async {
    // Initialize health service silently in background
    await _health.initialize();
    await _health.requestAuthorization();

    // Listen for step updates
    _stepsSubscription = _health.stepsStream.listen((steps) {
      setState(() {
        _progress = Progress(
          stepsToday: steps,
          workoutMinutesToday: _progress.workoutMinutesToday,
        );
      });
    });

    // Initial fetch
    final steps = await _health.fetchStepsToday();
    setState(() {
      _progress = Progress(
        stepsToday: steps,
        workoutMinutesToday: _progress.workoutMinutesToday,
      );
    });
  }

  @override
  void dispose() {
    _stepsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final rulesJson = prefs.getString('rules');
    if (rulesJson != null) {
      final List<dynamic> decoded = jsonDecode(rulesJson);
      setState(() {
        _rules = decoded.map((r) => Rule.fromJson(r)).toList();
      });
    }
  }

  Future<void> _saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    final rulesJson = jsonEncode(_rules.map((r) => r.toJson()).toList());
    await prefs.setString('rules', rulesJson);
  }

  void _addRule(Rule rule) {
    setState(() => _rules.add(rule));
    _saveRules();
  }

  void _deleteRule(String id) {
    setState(() => _rules.removeWhere((r) => r.id == id));
    _saveRules();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Subtle step counter bar (non-intrusive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.directions_walk, size: 14, color: AppColors.textDim),
                  const SizedBox(width: 4),
                  Text(
                    '${_progress.stepsToday.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _progress.stepsToday >= 10000 ? AppColors.green : AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            // Header
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.metal,
                border: Border.all(color: AppColors.amberDim, width: 2),
              ),
              child: const Center(
                child: Text(
                  '◆ TOTAL CONTROL ◆',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.amber,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),

            // Subtitle
            const Text(
              'UNTIL \u2022 DURING \u2022 ALLOW',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textDim,
              ),
            ),

            const SizedBox(height: 12),

            // Rules list
            Expanded(
              child: _rules.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _rules.length,
                      itemBuilder: (ctx, i) => _buildRuleCard(_rules[i]),
                    ),
            ),

            // Add button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showAddRuleDialog(context),
                  child: const Text('+ ADD RULE'),
                ),
              ),
            ),

            // Status
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _rules.isEmpty ? 'NO RULES SET' : 'PROTECTION ACTIVE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _rules.isEmpty ? AppColors.textDim : AppColors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: AppColors.textDim),
          const SizedBox(height: 16),
          const Text(
            'No rules yet',
            style: TextStyle(color: AppColors.text, fontSize: 24),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap + ADD RULE to create one',
            style: TextStyle(color: AppColors.textDim, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(Rule rule) {
    final (blocked, status) = _progress.getRuleStatus(rule);
    // For allowDuring, "allowed" = not blocked (green). For others, "allowed" = not blocked.
    final isAllowed = !blocked;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.metal,
        border: Border.all(
          color: isAllowed ? AppColors.greenDim : AppColors.redDim,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Status indicator
            SizedBox(
              width: 100,
              child: Column(
                children: [
                  Icon(
                    isAllowed ? Icons.lock_open : Icons.lock,
                    color: isAllowed ? AppColors.green : AppColors.red,
                    size: 36,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAllowed ? 'ALLOWED' : 'BLOCKED',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isAllowed ? AppColors.green : AppColors.red,
                    ),
                  ),
                ],
              ),
            ),

            // Rule info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: _getModeColor(rule.mode).withOpacity(0.2),
                      border: Border.all(color: _getModeColor(rule.mode), width: 2),
                    ),
                    child: Text(
                      rule.modeLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getModeColor(rule.mode),
                      ),
                    ),
                  ),
                  Text(
                    rule.items.take(2).join(", ") + (rule.items.length > 2 ? " +${rule.items.length - 2}" : ""),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rule.conditions.map((c) => c.describe()).join(' + '),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.amber,
                    ),
                  ),
                  if (rule.exceptions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'UNLESS ${_formatExceptions(rule.exceptions)}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.green,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),

            // Delete button
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.red),
              onPressed: () => _confirmDelete(rule),
            ),
          ],
        ),
      ),
    );
  }

  Color _getModeColor(RuleMode mode) {
    switch (mode) {
      case RuleMode.until:
        return AppColors.amber;
      case RuleMode.during:
        return AppColors.red;
      case RuleMode.allowDuring:
        return AppColors.green;
    }
  }

  void _confirmDelete(Rule rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Delete Rule?', style: TextStyle(color: AppColors.amber)),
        content: Text(rule.describe(), style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRule(rule.id);
            },
            child: const Text('DELETE', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context) {
    final itemsController = TextEditingController();
    final valueController = TextEditingController(text: '10000');
    final value2Controller = TextEditingController(text: '');
    final exceptionsController = TextEditingController();
    RuleMode selectedMode = RuleMode.until;
    ConditionType selectedType = ConditionType.steps;
    List<Condition> conditions = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.panel,
          insetPadding: const EdgeInsets.only(left: 16, right: 16, top: 120, bottom: 50),
          child: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Mode tabs - only selected mode is boxed
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: RuleMode.values.map((mode) {
                    final isSelected = mode == selectedMode;
                    final label = mode == RuleMode.until ? 'UNTIL' : mode == RuleMode.during ? 'DURING' : 'ALLOW';
                    return GestureDetector(
                      onTap: () => setDialogState(() {
                        selectedMode = mode;
                        if (mode != RuleMode.until) {
                          selectedType = ConditionType.timeRange;
                          valueController.text = '09:00';
                          value2Controller.text = '17:00';
                        }
                      }),
                      child: isSelected
                          ? Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: _getModeColor(mode),
                                border: Border.all(color: _getModeColor(mode), width: 2),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: AppColors.bg,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: _getModeColor(mode).withOpacity(0.7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // SENTENCE STYLE: "DON'T LET ME [____] UNTIL [____]"
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selectedMode == RuleMode.allowDuring
                        ? AppColors.green.withOpacity(0.15)
                        : AppColors.red.withOpacity(0.15),
                    border: Border.all(
                      color: selectedMode == RuleMode.allowDuring ? AppColors.green : AppColors.red,
                      width: 3,
                    ),
                  ),
                  child: Text(
                    selectedMode == RuleMode.allowDuring ? "ALLOW ME TO" : "DON'T LET ME",
                    style: TextStyle(
                      color: selectedMode == RuleMode.allowDuring ? AppColors.green : AppColors.red,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Apps/sites input box with "use" prefix
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.metal,
                    border: Border.all(color: AppColors.amber, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Text('use ', style: TextStyle(color: AppColors.textDim, fontSize: 20)),
                      Expanded(
                        child: TextField(
                          controller: itemsController,
                          style: const TextStyle(color: AppColors.amber, fontSize: 20, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: 'NETFLIX, AMAZON PRIME...',
                            hintStyle: TextStyle(color: AppColors.amberDim, fontSize: 20),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Quick category buttons with < > navigation
                Row(
                  children: [
                    const Text('<', style: TextStyle(color: AppColors.textDim, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: BlockCategory.presets.map((cat) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () {
                                  final current = itemsController.text.isEmpty
                                      ? <String>[]
                                      : itemsController.text.split(',').map((s) => s.trim()).toList();
                                  current.addAll(cat.items);
                                  itemsController.text = current.toSet().join(', ');
                                  setDialogState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.textDim),
                                  ),
                                  child: Text('${cat.icon} ${cat.name}', style: const TextStyle(color: AppColors.text, fontSize: 14)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('>', style: TextStyle(color: AppColors.textDim, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),

                const SizedBox(height: 20),

                // Existing conditions
                if (conditions.isNotEmpty) ...[
                  ...conditions.asMap().entries.map((entry) {
                    final i = entry.key;
                    final c = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.metal,
                        border: Border.all(color: AppColors.green, width: 2),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${selectedMode == RuleMode.until ? "UNTIL" : "DURING"} ',
                            style: const TextStyle(color: AppColors.text, fontSize: 18),
                          ),
                          Expanded(
                            child: Text(
                              c.describe(),
                              style: const TextStyle(color: AppColors.green, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setDialogState(() => conditions.removeAt(i)),
                            child: const Icon(Icons.close, color: AppColors.red, size: 24),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  const Text('+ AND', style: TextStyle(color: AppColors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                ],

                // UNTIL keyword - highlighted box
                if (conditions.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withOpacity(0.15),
                      border: Border.all(color: AppColors.amber, width: 3),
                    ),
                    child: Text(
                      selectedMode == RuleMode.until ? 'UNTIL' : 'DURING',
                      style: const TextStyle(color: AppColors.amber, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                if (conditions.isEmpty) const SizedBox(height: 12),

                // Condition type chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _getConditionTypesForMode(selectedMode).map((type) {
                    final isSelected = type == selectedType;
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() => selectedType = type);
                        switch (type) {
                          case ConditionType.steps:
                            valueController.text = '10000';
                          case ConditionType.time:
                            valueController.text = '17:00';
                          case ConditionType.timeRange:
                            valueController.text = '09:00';
                            value2Controller.text = '17:00';
                          case ConditionType.workout:
                            valueController.text = '30';
                          default:
                            valueController.text = '';
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.green : AppColors.metal,
                          border: Border.all(color: AppColors.green, width: 2),
                        ),
                        child: Text(
                          _getConditionName(type),
                          style: TextStyle(
                            color: isSelected ? AppColors.bg : AppColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),

                // Condition value input - FULL PHRASE INSIDE BOX
                if (_needsValueInput(selectedType)) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.metal,
                      border: Border.all(color: AppColors.green, width: 2),
                    ),
                    child: Row(
                      children: [
                        // Prefix text based on condition type
                        Text(
                          selectedType == ConditionType.steps ? 'I walk ' :
                          selectedType == ConditionType.workout ? 'I workout ' :
                          selectedType == ConditionType.time ? 'it\'s ' :
                          selectedType == ConditionType.timeRange ? 'between ' : '',
                          style: const TextStyle(color: AppColors.textDim, fontSize: 20),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: valueController,
                            style: const TextStyle(color: AppColors.green, fontSize: 24, fontWeight: FontWeight.bold),
                            keyboardType: selectedType == ConditionType.steps || selectedType == ConditionType.workout
                                ? TextInputType.number
                                : TextInputType.text,
                            decoration: InputDecoration(
                              hintText: _getHint(selectedType),
                              hintStyle: const TextStyle(color: AppColors.greenDim, fontSize: 24),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (selectedType == ConditionType.timeRange) ...[
                          const Text(' - ', style: TextStyle(color: AppColors.green, fontSize: 24)),
                          Expanded(
                            child: TextField(
                              controller: value2Controller,
                              style: const TextStyle(color: AppColors.green, fontSize: 24, fontWeight: FontWeight.bold),
                              decoration: const InputDecoration(
                                hintText: '17:00',
                                hintStyle: TextStyle(color: AppColors.greenDim, fontSize: 24),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                        // Suffix text
                        Text(
                          selectedType == ConditionType.steps ? 'steps...' :
                          selectedType == ConditionType.workout ? 'minutes...' : '',
                          style: const TextStyle(color: AppColors.textDim, fontSize: 20),
                        ),
                      ],
                    ),
                  ),
                ],

                // + ADD CONDITION button
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.green, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      final condition = _buildCondition(selectedType, valueController.text, value2Controller.text);
                      setDialogState(() {
                        conditions.add(condition);
                        selectedType = ConditionType.steps;
                        valueController.text = '10000';
                      });
                    },
                    child: Text(
                      conditions.isEmpty ? 'SET CONDITION' : '+ AND (add another)',
                      style: const TextStyle(color: AppColors.green, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // UNLESS exceptions
                const SizedBox(height: 20),
                const Text('UNLESS (always allow):', style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                const SizedBox(height: 4),
                TextField(
                  controller: exceptionsController,
                  style: const TextStyle(color: AppColors.green, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'WhatsApp, music.youtube.com...',
                    hintStyle: TextStyle(color: AppColors.textDim, fontSize: 16),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.green)),
                    isDense: true,
                  ),
                ),

                // Action buttons
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CANCEL', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        final items = itemsController.text
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();

                        if (items.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter at least one app/site')),
                          );
                          return;
                        }

                        if (conditions.isEmpty) {
                          conditions.add(_buildCondition(selectedType, valueController.text, value2Controller.text));
                        }

                        final exceptions = exceptionsController.text
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();

                        // Auto-add music.youtube.com as exception when blocking YouTube
                        if (selectedMode != RuleMode.allowDuring) {
                          final hasYouTube = items.any((item) =>
                              item.toLowerCase().contains('youtube'));
                          if (hasYouTube && !exceptions.contains('music.youtube.com')) {
                            exceptions.add('music.youtube.com');
                          }
                        }

                        final rule = Rule(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          items: items,
                          mode: selectedMode,
                          conditions: conditions,
                          exceptions: exceptions,
                        );

                        Navigator.pop(ctx);
                        _addRule(rule);
                      },
                      child: const Text('CREATE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  String _getModeName(RuleMode mode) {
    switch (mode) {
      case RuleMode.until:
        return 'NO...UNTIL';
      case RuleMode.during:
        return 'NO...DURING';
      case RuleMode.allowDuring:
        return 'ONLY DURING';
    }
  }

  String _getConditionName(ConditionType type) {
    switch (type) {
      case ConditionType.steps:
        return 'Steps';
      case ConditionType.time:
        return 'Time';
      case ConditionType.timeRange:
        return 'Hours';
      case ConditionType.workout:
        return 'Workout';
      case ConditionType.location:
        return 'Location';
      case ConditionType.tomorrow:
        return 'Tomorrow';
      case ConditionType.password:
        return 'Password';
      case ConditionType.schedule:
        return 'Days';
    }
  }

  List<ConditionType> _getConditionTypesForMode(RuleMode mode) {
    switch (mode) {
      case RuleMode.until:
        // UNTIL: steps, time, workout, location, tomorrow, password
        return [
          ConditionType.steps,
          ConditionType.time,
          ConditionType.workout,
          ConditionType.location,
          ConditionType.tomorrow,
          ConditionType.password,
        ];
      case RuleMode.during:
      case RuleMode.allowDuring:
        // DURING: time range, location, workout, schedule
        return [
          ConditionType.timeRange,
          ConditionType.location,
          ConditionType.workout,
          ConditionType.schedule,
        ];
    }
  }

  bool _needsValueInput(ConditionType type) {
    return type != ConditionType.tomorrow && type != ConditionType.password;
  }

  String _getHint(ConditionType type) {
    switch (type) {
      case ConditionType.steps:
        return '10000';
      case ConditionType.time:
        return '17:00';
      case ConditionType.timeRange:
        return '09:00 - 17:00';
      case ConditionType.workout:
        return '30 (minutes)';
      case ConditionType.location:
        return 'Gym';
      case ConditionType.schedule:
        return 'weekdays';
      default:
        return '';
    }
  }

  String _formatExceptions(List<String> exceptions) {
    final formatted = exceptions.map((e) {
      // Show friendly names for common exceptions
      if (e.toLowerCase() == 'music.youtube.com') return 'Music';
      if (e.toLowerCase() == 'music') return 'Music';
      return e;
    }).take(2).toList();
    final suffix = exceptions.length > 2 ? ' +${exceptions.length - 2}' : '';
    return formatted.join(', ') + suffix;
  }

  Condition _buildCondition(ConditionType type, String value, [String? value2]) {
    switch (type) {
      case ConditionType.steps:
        return Condition(type: type, stepsTarget: int.tryParse(value) ?? 10000);
      case ConditionType.time:
        return Condition(type: type, timeTarget: value);
      case ConditionType.timeRange:
        return Condition(
          type: type,
          timeRange: TimeRange(
            startTime: value.isNotEmpty ? value : '09:00',
            endTime: value2?.isNotEmpty == true ? value2! : '17:00',
          ),
        );
      case ConditionType.workout:
        return Condition(type: type, workoutMinutes: int.tryParse(value) ?? 30);
      case ConditionType.location:
        return Condition(type: type, location: Location(name: value, latitude: 0, longitude: 0));
      case ConditionType.schedule:
        return Condition(
          type: type,
          schedule: value == 'weekends' ? Schedule.weekends() : Schedule.weekdays(),
        );
      case ConditionType.tomorrow:
      case ConditionType.password:
        return Condition(type: type);
    }
  }
}
