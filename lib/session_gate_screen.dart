import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'verification_screen.dart';
import 'login_screen.dart';
import 'package:camera/camera.dart';

class SessionGateScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String institutionId;
  final List<Map<String, dynamic>> courseUnits;

  const SessionGateScreen({
    super.key,
    required this.cameras,
    required this.institutionId,
    required this.courseUnits,
  });

  @override
  State<SessionGateScreen> createState() => _SessionGateScreenState();
}

class _SessionGateScreenState extends State<SessionGateScreen> {
  // ── State ──────────────────────────────────────────────────────────────
  Map<String, dynamic>? _selectedCourseUnit;
  Map<String, dynamic>? _selectedLecturer;
  List<Map<String, dynamic>> _lecturers = [];
  bool _loadingLecturers = false;
  bool _creatingSession = false;
  String? _coordinatorId;

  @override
  void initState() {
    super.initState();
    _loadCoordinatorId();
    // Auto-select if only one course unit
    if (widget.courseUnits.length == 1) {
      _selectedCourseUnit = widget.courseUnits.first;
      _loadLecturers(widget.courseUnits.first['id']);
    }
  }

  // ── Load coordinator profile id ────────────────────────────────────────
  Future<void> _loadCoordinatorId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _coordinatorId = user.id);
  }

  Future<void> _logout() async {
  await Supabase.instance.client.auth.signOut();
  if (!mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => LoginScreen(cameras: widget.cameras)),
    (route) => false,
  );
}

  // ── Load lecturers assigned to selected course unit ────────────────────
  Future<void> _loadLecturers(String courseUnitId) async {
    setState(() {
      _loadingLecturers = true;
      _selectedLecturer = null;
      _lecturers = [];
    });

    try {
      // Query lecturer_courses junction → get lecturer profiles
      final rows = await Supabase.instance.client
          .from('lecturer_courses')
          .select('lecturer_id, profiles!lecturer_id(id, full_name, email)')
          .eq('course_unit_id', courseUnitId)
          .eq('institution_id', widget.institutionId);

      debugPrint('_loadLecturers rows: $rows'); // ← here

      final List<Map<String, dynamic>> lecturers = [];
      for (final row in rows) {
        // The joined `profiles` relation may be returned as a Map or a
        // single-element List depending on the client/driver; handle both.
        var profile = row['profiles'];
        if (profile is List && profile.isNotEmpty) profile = profile.first;
        if (profile != null) {
          lecturers.add({
            'id': profile['id'],
            'full_name': profile['full_name'] ?? 'Unknown',
            'email': profile['email'] ?? '',
          });
        }
      }

      debugPrint('_loadLecturers lecturers parsed: $lecturers');
      debugPrint('setting lecturer: ${lecturers.length} found, auto-select: ${lecturers.length == 1}');

      if (mounted) {
        setState(() {
          _lecturers = lecturers;
          _loadingLecturers = false;
          if (lecturers.length == 1) {
            _selectedLecturer = lecturers.first;
          }
        });
      }
    } catch (e) {
      debugPrint('_loadLecturers error: $e');
      if (mounted) setState(() => _loadingLecturers = false);
    }
  }

  // ── Create session and navigate to verification ────────────────────────
  Future<void> _beginSession() async {
    if (_selectedCourseUnit == null || _selectedLecturer == null) return;
    setState(() => _creatingSession = true);

    try {
      if (_coordinatorId == null) {
        await _loadCoordinatorId();
      }
      if (_coordinatorId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not load coordinator profile. Try again.'),
            ),
          );
          setState(() => _creatingSession = false);
        }
        return;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final unitName = _selectedCourseUnit!['name'] ?? 'Session';
      final dateStr = _formatDate(DateTime.now());

      final result = await Supabase.instance.client
          .from('sessions')
          .insert({
            'institution_id': widget.institutionId,
            'name': '$unitName - $dateStr',
            'course_unit_id': _selectedCourseUnit!['id'],
            'lecturer_id': _selectedLecturer!['id'],
            'coordinator_id': _coordinatorId,
            'started_at': now,
            'status': 'active',
          })
          .select('id')
          .single();

      // Ensure sessionId is a string (DB may return int).
      final sessionId = result['id'].toString();

      if (!mounted) return;

      // Navigate to verification screen with session context
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VerificationScreen(
            cameras: widget.cameras,
            institutionId: widget.institutionId,
            courseUnits: [_selectedCourseUnit!],
            sessionId: sessionId,
            lecturerName: _selectedLecturer!['full_name'],
            lecturerId: _selectedLecturer!['id'],
          ),
        ),
      );
    } catch (e) {
      debugPrint('_beginSession error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create session: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _creatingSession = false);
      }
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool canBegin =
        _selectedCourseUnit != null && _selectedLecturer != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.play_circle_outline,
                            color: Colors.cyanAccent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Session',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5)),
                          Text('Set up before taking attendance',
                              style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white38),
                    tooltip: 'Sign out',
                    onPressed: _logout,
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // ── Step 1: Course Unit ────────────────────────────────────
              _StepLabel(number: '1', label: 'Select Course Unit'),
              const SizedBox(height: 12),

              if (widget.courseUnits.isEmpty)
                _EmptyHint(
                    message: 'No course units assigned. Contact your admin.')
              else
                ...widget.courseUnits.map((unit) => _SelectionTile(
                      title: unit['name'] ?? unit['id'],
                      subtitle: unit['code'] ?? '',
                      isSelected: _selectedCourseUnit?['id'] == unit['id'],
                      icon: Icons.menu_book_outlined,
                      onTap: () {
                        setState(() {
                          _selectedCourseUnit = unit;
                          _selectedLecturer = null;
                        });
                        _loadLecturers(unit['id']);
                      },
                    )),

              const SizedBox(height: 32),

              // ── Step 2: Lecturer ───────────────────────────────────────
              _StepLabel(
                number: '2',
                label: 'Select Lecturer',
                dimmed: _selectedCourseUnit == null,
              ),
              const SizedBox(height: 12),

              if (_selectedCourseUnit == null)
                _EmptyHint(message: 'Select a course unit first.')
              else if (_loadingLecturers)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: Colors.cyanAccent, strokeWidth: 2),
                  ),
                )
              else if (_lecturers.isEmpty)
                _EmptyHint(
                    message:
                        'No lecturers assigned to this unit. Contact admin.')
              else
                ..._lecturers.map((lec) => _SelectionTile(
                      title: lec['full_name'],
                      subtitle: lec['email'],
                      isSelected: _selectedLecturer?['id'] == lec['id'],
                      icon: Icons.person_outline,
                      onTap: () =>
                          setState(() => _selectedLecturer = lec),
                    )),

              const Spacer(),

              // ── Session summary ────────────────────────────────────────
              if (canBegin) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.cyanAccent.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.cyanAccent, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_selectedCourseUnit!['name']}  ·  ${_selectedLecturer!['full_name']}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Begin button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        canBegin ? Colors.cyanAccent : Colors.grey[800],
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: canBegin ? 4 : 0,
                  ),
                  onPressed: canBegin && !_creatingSession
                      ? _beginSession
                      : null,
                  child: _creatingSession
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2.5),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_arrow_rounded, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              canBegin
                                  ? 'BEGIN SESSION'
                                  : 'SELECT UNIT & LECTURER',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  final String number;
  final String label;
  final bool dimmed;

  const _StepLabel({
    required this.number,
    required this.label,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dimmed
                ? Colors.grey[800]
                : Colors.cyanAccent.withOpacity(0.15),
            border: Border.all(
              color: dimmed ? Colors.grey[700]! : Colors.cyanAccent,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: dimmed ? Colors.grey : Colors.cyanAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: dimmed ? Colors.grey : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  const _SelectionTile({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.cyanAccent.withOpacity(0.1)
              : Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.grey[800]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.cyanAccent : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: Colors.cyanAccent, size: 18),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;
  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.grey, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}