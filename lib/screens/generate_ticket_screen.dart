import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class GenerateTicketScreen extends StatefulWidget {
  // Global key to allow parent (Home) to trigger refresh on mobile app bar
  static final GlobalKey<_GenerateTicketScreenState> globalKey =
      GlobalKey<_GenerateTicketScreenState>();
  final VoidCallback? onBack;
  const GenerateTicketScreen({super.key, this.onBack});

  @override
  State<GenerateTicketScreen> createState() => _GenerateTicketScreenState();
}

class _GenerateTicketScreenState extends State<GenerateTicketScreen> {
  bool _isSuperAdmin = false;
  bool _loading = true;
  String? _error;

  // Student form state
  String? _level1; // request | query | complaint
  String? _level2; // depends on level1
  final TextEditingController _contentCtrl = TextEditingController();
  bool _submitting = false;

  // Admin list state
  bool _listLoading = false;
  List<Map<String, dynamic>> _tickets = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  // Public method to allow external refresh (from Home mobile app bar)
  void refreshTickets() {
    if (!_listLoading) {
      _loadTickets();
    }
  }

  Future<void> _init() async {
    try {
      final user = await ApiService.getCurrentUser();
      final isSA = (user?['role'] == 'Admin') &&
          ((user?['is_super_admin'] == 1) || (user?['is_super_admin'] == '1'));
      setState(() {
        _isSuperAdmin = isSA;
      });
      if (isSA) {
        await _loadTickets();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _level1Options => const ['request', 'query', 'complaint'];

  List<String> get _level2Options {
    switch (_level1) {
      case 'request':
        return const ['fee concession', 'fines waiver'];
      case 'query':
        return const ['subject related', 'portal not working'];
      case 'complaint':
        return const ['teacher', 'student'];
      default:
        return const [];
    }
  }

  Future<void> _createTicket() async {
    if (_level1 == null ||
        _level2 == null ||
        _contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields')),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ApiService.createTicket(
        level1: _level1!,
        level2: _level2!,
        content: _contentCtrl.text.trim(),
      );
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ticket created')),
          );
          setState(() {
            _level1 = null;
            _level2 = null;
            _contentCtrl.clear();
          });
        }
      } else {
        throw Exception(res['error'] ?? 'Failed to create ticket');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _loadTickets() async {
    setState(() {
      _listLoading = true;
      _error = null;
    });
    try {
      final items = await ApiService.listTickets();
      if (!mounted) return;
      setState(() {
        _tickets = items;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _tickets = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _listLoading = false;
        });
      }
    }
  }

  Future<void> _sendReply(int ticketId, String replyKey,
      {String? status}) async {
    try {
      final res = await ApiService.replyTicket(
          ticketId: ticketId, replyKey: replyKey, status: status);
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reply sent')),
          );
          await _loadTickets();
        }
      } else {
        throw Exception(res['error'] ?? 'Failed to send reply');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reply error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const primaryBlue = Color(0xFF1E3A8A);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final bool isWide = MediaQuery.of(context).size.width >= 768;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isWide
          ? AppBar(
              backgroundColor: primaryBlue,
              elevation: 0,
              toolbarHeight: 64,
              leadingWidth: 48,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Back',
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              title: Text(
                'Generate Ticket',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _listLoading ? null : _loadTickets,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isSuperAdmin
            ? _buildAdminView(onSurface)
            : _buildStudentView(onSurface),
      ),
    );
  }

  Widget _buildStudentView(Color onSurface) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          // Mobile layout: Form on top, tickets below
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Create ticket form
                _buildStudentForm(onSurface),
                const SizedBox(height: 24),
                // All tickets display
                SizedBox(
                  height: 400,
                  child: _buildAllTicketsDisplay(onSurface),
                ),
              ],
            ),
          );
        } else {
          // Desktop layout: Side by side, full-width stretch
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Create ticket form - left side
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 500,
                  child: _buildStudentForm(onSurface),
                ),
              ),
              const SizedBox(width: 20),
              // All tickets display - right side
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 500,
                  child: _buildAllTicketsDisplay(onSurface),
                ),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildStudentForm(Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!,
                style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
        Text('Category', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _level1,
          items: _level1Options
              .map((e) =>
                  DropdownMenuItem(value: e, child: Text(_capitalize(e))))
              .toList(),
          onChanged: (val) {
            setState(() {
              _level1 = val;
              _level2 = null;
            });
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1E3A8A),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA).withValues(alpha: 0.5)
                    : const Color(0xFF1E3A8A).withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1E3A8A),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black
                : Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text('Type', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _level2,
          items: _level2Options
              .map((e) =>
                  DropdownMenuItem(value: e, child: Text(_capitalize(e))))
              .toList(),
          onChanged: (val) => setState(() => _level2 = val),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1E3A8A),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA).withValues(alpha: 0.5)
                    : const Color(0xFF1E3A8A).withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1E3A8A),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black
                : Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text('Content', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: _contentCtrl,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: 'Describe your ticket...',
            hintStyle: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF60A5FA).withValues(alpha: 0.6)
                  : const Color(0xFF6B7280),
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1E3A8A),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA).withValues(alpha: 0.5)
                    : const Color(0xFF1E3A8A).withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1E3A8A),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black
                : Colors.white,
          ),
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF60A5FA)
                : const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _submitting ? null : _createTicket,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(_submitting ? 'Submitting...' : 'Submit'),
        ),
      ],
    );
  }

  Widget _buildAdminView(Color onSurface) {
    return _buildAdminList(onSurface);
  }

  Widget _buildAdminList(Color onSurface) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color lightCard = Color(0xFFE7E0DE);
    const Color lightBorder = Color(0xFFD9D2D0);
    const Color accentBlue = Color(0xFF1E3A8A);
    if (_listLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
          child:
              Text(_error!, style: GoogleFonts.inter(color: Colors.redAccent)));
    }
    if (_tickets.isEmpty) {
      return Center(
          child: Text('No tickets found',
              style:
                  GoogleFonts.inter(color: onSurface.withValues(alpha: 0.75))));
    }
    return ListView.separated(
      itemCount: _tickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final t = _tickets[index];
        final id = int.tryParse(t['id'].toString());
        final level1 = (t['level1'] ?? '').toString();
        final level2 = (t['level2'] ?? '').toString();
        final content = (t['content'] ?? '').toString();
        final status = (t['status'] ?? '').toString();
        final creator =
            (t['creator_name'] ?? t['creator_email'] ?? 'Student').toString();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : lightCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : lightBorder,
            ),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: accentBlue.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                      '#${id ?? '-'}  ${_capitalize(level1)} • ${_capitalize(level2)}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: isDark ? onSurface : accentBlue,
                      )),
                  const Spacer(),
                  _StatusChip(status: status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                content,
                style: GoogleFonts.inter(
                  color: isDark
                      ? onSurface.withValues(alpha: 0.85)
                      : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text('By: $creator',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: onSurface.withValues(alpha: 0.7))),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ReplyBtn(
                      label: 'Acknowledge',
                      onTap: id == null
                          ? null
                          : () => _sendReply(id, 'acknowledged',
                              status: 'in_progress')),
                  _ReplyBtn(
                      label: 'In Review',
                      onTap: id == null
                          ? null
                          : () => _sendReply(id, 'in_review',
                              status: 'in_progress')),
                  _ReplyBtn(
                      label: 'Resolved',
                      onTap: id == null
                          ? null
                          : () =>
                              _sendReply(id, 'resolved', status: 'resolved')),
                  _ReplyBtn(
                      label: 'Close',
                      onTap: id == null
                          ? null
                          : () => _sendReply(id, 'closed', status: 'closed')),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildAllTicketsDisplay(Color onSurface) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color accentBlue = Color(0xFF1E3A8A);
    const Color lightCard = Color(0xFFE7E0DE);
    const Color lightBorder = Color(0xFFD9D2D0);
    final Color accent = isDark ? const Color(0xFF60A5FA) : accentBlue;
    // Removed unused local variable 'isMobile'
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? accent.withValues(alpha: 0.1) : lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? accent.withValues(alpha: 0.3) : lightBorder,
          width: 2,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: accentBlue.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row removed; refresh is placed in the app bar to avoid duplication
          Expanded(
            child: _listLoading
                ? const Center(child: CircularProgressIndicator())
                : _tickets.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.confirmation_number_outlined,
                              size: 48,
                              color: accent,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No Tickets Found',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Create your first support ticket above',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _tickets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final ticket = _tickets[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? accent.withValues(alpha: 0.25)
                                    : lightBorder,
                                width: 1,
                              ),
                              boxShadow: isDark
                                  ? []
                                  : [
                                      BoxShadow(
                                        color:
                                            accentBlue.withValues(alpha: 0.04),
                                        blurRadius: 14,
                                        offset: const Offset(0, 7),
                                      ),
                                    ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '#${ticket['id']} - ${_capitalize(ticket['level1'] ?? '')} (${_capitalize(ticket['level2'] ?? '')})',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              isDark ? onSurface : accentBlue,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(ticket['status'])
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color:
                                              _getStatusColor(ticket['status']),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        (ticket['status'] ?? 'open')
                                            .toString()
                                            .toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              _getStatusColor(ticket['status']),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  ticket['content']?.toString() ?? '',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: onSurface.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 14,
                                      color: onSurface.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      ticket['creator_name']?.toString() ??
                                          ticket['creator_email']?.toString() ??
                                          'Unknown',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: onSurface.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatTicketDate(
                                          ticket['created_at']?.toString()),
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatTicketDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.purple;
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }
}

class _StatusChip extends StatelessWidget {
  final String status; // open | in_progress | resolved | closed
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'open':
        c = const Color(0xFF8B5CF6);
        break;
      case 'in_progress':
        c = const Color(0xFFF59E0B);
        break;
      case 'resolved':
        c = const Color(0xFF10B981);
        break;
      case 'closed':
        c = const Color(0xFF64748B);
        break;
      default:
        c = Theme.of(context).colorScheme.onSurface;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.7)),
      ),
      child: Text(status.toUpperCase(),
          style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

class _ReplyBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _ReplyBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF60A5FA)
            : const Color(0xFF1E3A8A),
        foregroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
