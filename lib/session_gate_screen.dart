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
  bool _checkingSession = false;
  String? _coordinatorId;

  @override
  void initState() {
    super.initState();
    _loadCoordinatorId();
    _checkExistingSession();
    // Auto-select if only one course unit
    if (widget.courseUnits.length == 1) {
      _selectedCourseUnit = widget.courseUnits.first;
      _loadLecturers(widget.courseUnits.first['id']);
    }
  }

  // ── Check for existing active session ──────────────────────────────────
  Future<void> _checkExistingSession() async {
    setState(() => _checkingSession = true);
    try {
      final result = await Supabase.instance.client
          .from('sessions')
          .select('id, lecturer_id, course_unit_id')
          .eq('institution_id', widget.institutionId)
          .eq('status', 'active')
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      if (result == null) return;

      // Fetch lecturer name from profiles
      final lecturerProfile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', result['lecturer_id'])
          .single();

      if (!mounted) return;

      // Navigate to VerificationScreen with existing session
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationScreen(
            cameras: widget.cameras,
            institutionId: widget.institutionId,
            sessionId: result['id'].toString(),
            lecturerName: lecturerProfile['full_name'] ?? 'Unknown',
            lecturerId: result['lecturer_id'],
            courseUnitId: result['course_unit_id'],
          ),
        ),
      );
    } catch (e) {
      debugPrint('_checkExistingSession error: $e');
      // Continue normally if check fails
    } finally {
      if (mounted) setState(() => _checkingSession = false);
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationScreen(
            cameras: widget.cameras,
            institutionId: widget.institutionId,
            sessionId: sessionId,
            lecturerName: _selectedLecturer!['full_name'],
            lecturerId: _selectedLecturer!['id'],
            courseUnitId: _selectedCourseUnit!['id'],
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
    // Show loading indicator while checking for existing session
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withOpacity(0.2),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_circle_outline,
                            color: Colors.cyanAccent, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('New Session',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5)),
                          Text('Set up before taking attendance',
                              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.logout, color: Colors.grey[400]),
                    tooltip: 'Sign out',
                    onPressed: _logout,
                  ),
                ],
              ),

              const SizedBox(height: 48),

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
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.cyanAccent.withOpacity(0.3), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(0.1),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.cyanAccent, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${_selectedCourseUnit!['name']}  ·  ${_selectedLecturer!['full_name']}',
                          style: TextStyle(
                              color: Colors.grey[300], fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── Begin button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        canBegin ? Colors.cyanAccent : Colors.grey[800],
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: canBegin ? 8 : 0,
                    shadowColor: canBegin ? Colors.cyanAccent.withOpacity(0.5) : null,
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
                            const Icon(Icons.play_arrow_rounded, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              canBegin
                                  ? 'BEGIN SESSION'
                                  : 'SELECT UNIT & LECTURER',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: 1.2,
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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.cyanAccent.withOpacity(0.12)
              : Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.grey[800]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ] : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.cyanAccent : Colors.grey[500],
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: Colors.cyanAccent, size: 20),
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