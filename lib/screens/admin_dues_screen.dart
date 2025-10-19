import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'home.dart';

class AdminDuesScreen extends StatefulWidget {
  const AdminDuesScreen({super.key});

  @override
  State<AdminDuesScreen> createState() => _AdminDuesScreenState();
}

class _AdminDuesScreenState extends State<AdminDuesScreen> {
  final TextEditingController _typeAheadController = TextEditingController();
  String _searchType = 'name';
  bool _isLoading = false;
  Map<String, dynamic>? _selectedStudent;
  List<Map<String, dynamic>> _recentSearches = [];
  
  // Filters state
  String? _selectedClassFilter;
  final List<String> _classOptions = const [
    'Nursery', 'KG',
    '1st Grade', '2nd Grade', '3rd Grade', '4th Grade', '5th Grade',
    '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade',
    '11th Grade', '12th Grade',
  ];

  // Computed getters for dues amounts (supports snake_case and camelCase keys)
  double get totalDues {
    final v = _selectedStudent?['total_dues'] ?? _selectedStudent?['totalDues'] ?? 0;
    return (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
  }

  void _showFiltersDialog() {
    String tempSearchType = _searchType; // local state for dialog

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSBState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155), width: 1),
          ),
          title: Text(
            'Filters',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            height: 300,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Class', style: GoogleFonts.inter(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _classOptions.map((c) {
                      final selected = _selectedClassFilter == c;
                      return ChoiceChip(
                        label: Text(c),
                        selected: selected,
                        labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
                        selectedColor: const Color(0xFF1E40AF),
                        backgroundColor: const Color(0xFF0F172A),
                        shape: StadiumBorder(side: BorderSide(color: selected ? const Color(0xFF3B82F6) : const Color(0xFF334155))),
                        onSelected: (_) {
                          setSBState(() {
                            _selectedClassFilter = selected ? null : c;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('Search Mode', style: GoogleFonts.inter(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSBState(() => tempSearchType = 'roll'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: tempSearchType == 'roll' ? const Color(0xFF3B82F6) : const Color(0xFF334155)),
                            backgroundColor: tempSearchType == 'roll' ? const Color(0xFF1E40AF) : const Color(0xFF1E293B),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text('Search by Roll No', style: GoogleFonts.inter(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSBState(() => tempSearchType = 'name'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: tempSearchType == 'name' ? const Color(0xFF3B82F6) : const Color(0xFF334155)),
                            backgroundColor: tempSearchType == 'name' ? const Color(0xFF1E40AF) : const Color(0xFF1E293B),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text('Search by Name', style: GoogleFonts.inter(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _searchType = tempSearchType;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF)),
              child: const Text('APPLY'),
            ),
          ],
        ),
      ),
    );
  }

  double get paidAmount {
    final v = _selectedStudent?['paid_amount'] ?? _selectedStudent?['paidAmount'] ?? 0;
    return (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
  }

  double get remainingDues {
    final v = _selectedStudent?['remaining_dues'] ?? _selectedStudent?['remainingDues'];
    if (v != null) {
      return (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    }
    // Fallback compute
    return (totalDues - paidAmount).clamp(0, double.infinity).toDouble();
  }

  Future<List<Map<String, dynamic>>> _fetchStudents(String query) async {
    try {
      final response = await ApiService.searchStudents(query, _searchType);
      return response.cast<Map<String, dynamic>>();
    } catch (e) {
      // Debug: print('Error fetching students: $e');
      return [];
    }
  }

  void _saveRecentSearch(Map<String, dynamic> student) {
    if (!_recentSearches.any((s) => s['id'] == student['id'])) {
      setState(() => _recentSearches = [student, ..._recentSearches].take(5).toList());
    }
  }

  // removed unused dummy _students list

  // Note: Single dispose that clears all controllers

  void _searchStudent(String query) async {
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    
    try {
      final students = await _fetchStudents(query);
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (students.isNotEmpty) {
            _selectedStudent = students.first;
            _saveRecentSearch(_selectedStudent!);
            // No longer show popup - student details will appear on main screen
          } else {
            _selectedStudent = null;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No student found')),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedStudent = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error searching for student')),
        );
      }
    }
  }
  Widget _buildStudentDetailsCard() {
    if (_selectedStudent == null) return const SizedBox.shrink();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const accentBlue = Color(0xFF1E3A8A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: accentBlue.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with student name and close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student Profile',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : accentBlue,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedStudent!['name'] ?? 'N/A',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white.withValues(alpha: 0.85) : accentBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _selectedStudent = null),
                icon: Icon(Icons.close, color: isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.6)),
                style: IconButton.styleFrom(
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : accentBlue.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Student Information Grid
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Basic Information',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : accentBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('Roll No', _selectedStudent!['roll_number'] ?? 'N/A'),
                    _buildInfoRow('Class', _selectedStudent!['class_name'] ?? 'N/A'),
                    if (_selectedStudent!['section'] != null) 
                      _buildInfoRow('Section', _selectedStudent!['section']),
                    if (_selectedStudent!['phone'] != null)
                      _buildInfoRow('Contact', _selectedStudent!['phone']),
                    if (_selectedStudent!['parent_phone'] != null)
                      _buildInfoRow('Parent Contact', _selectedStudent!['parent_phone']),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dues Information',
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : accentBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('Total Dues', '₹${totalDues.toStringAsFixed(2)}'),
                    _buildInfoRow('Paid Amount', '₹${paidAmount.toStringAsFixed(2)}'),
                    _buildInfoRow(
                      'Remaining',
                      '₹${remainingDues.toStringAsFixed(2)}',
                      isHighlighted: true,
                    ),
                    if (_selectedStudent!['last_payment_date'] != null)
                      _buildInfoRow('Last Payment', _selectedStudent!['last_payment_date']),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                flex: 1,
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateChallanDialog(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E40AF),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: Text(
                    'Create\nChallan',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: ElevatedButton.icon(
                  onPressed: () => _showVerifyDialog(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.verified, size: 18),
                  label: Text(
                    'Verify',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: () => _showPaymentHistory(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1E40AF)),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.history, color: Color(0xFF3B82F6), size: 18),
                  label: Text(
                    'View\nHistory',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF3B82F6),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickChallanFile(StateSetter setState) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _challanPickedFile = file;
          _selectedChallanFileName = file.name;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Selected: ${file.name}'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting file: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _uploadChallanFile(StateSetter setState) {
    if (_challanPickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a file first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // File is selected and ready - the actual upload happens when SAVE is clicked
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('File selected: ${_challanPickedFile!.name}. Click SAVE to create challan.'),
        backgroundColor: const Color(0xFF059669),
      ),
    );
  }

  Future<void> _pickDueDate(StateSetter setState) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _challanDueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(primary: Color(0xFF1E40AF), surface: Color(0xFF1E293B)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _challanDueDate = picked);
    }
  }

  void _showCreateChallanDialog() {
    _challanTitleController.clear();
    _challanAmountController.clear();
    _challanCategory = 'fee';
    _challanDueDate = null;
    _selectedChallanFileName = null;

    bool modalSaving = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          const Color accentBlue = Color(0xFF1E3A8A);
          const Color lightCard = Color(0xFFE7E0DE);
          const Color lightBorder = Color(0xFFD9D2D0);
          final Color borderColor = isDark ? const Color(0xFF334155) : lightBorder;
          final Color focusedBorderColor = isDark ? const Color(0xFF1E40AF) : accentBlue;
          final Color labelColor = isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.8);
          final Color fieldFill = isDark ? const Color(0xFF0F172A) : Colors.white;

          Future<void> saveChallan() async {
            print('[DEBUG] saveChallan() called');
            if (!_challanFormKey.currentState!.validate()) {
              print('[DEBUG] Form validation failed');
              return;
            }
            if (_selectedStudent == null) {
              print('[DEBUG] No student selected');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a student first')),
              );
              return;
            }
            
            print('[DEBUG] Selected student: ${_selectedStudent!['id']} - ${_selectedStudent!['name']}');
            print('[DEBUG] Title: ${_challanTitleController.text.trim()}');
            print('[DEBUG] Amount: ${_challanAmountController.text}');
            print('[DEBUG] Category: $_challanCategory');
            print('[DEBUG] Due date: $_challanDueDate');
            print('[DEBUG] Picked file: ${_challanPickedFile?.name}');
            print('[DEBUG] File path: ${_challanPickedFile?.path}');
            print('[DEBUG] File bytes length: ${_challanPickedFile?.bytes?.length}');
            
            setState(() => modalSaving = true);
            try {
              final amount = double.tryParse(_challanAmountController.text);
              final due = _challanDueDate != null
                  ? '${_challanDueDate!.year.toString().padLeft(4,'0')}-${_challanDueDate!.month.toString().padLeft(2,'0')}-${_challanDueDate!.day.toString().padLeft(2,'0')}'
                  : null;
              final filePath = _challanPickedFile?.path;
              final fileBytes = _challanPickedFile?.bytes;
              final fileName = _challanPickedFile?.name;
              
              print('[DEBUG] Parsed amount: $amount');
              print('[DEBUG] Formatted due date: $due');
              print('[DEBUG] Calling ApiService.createChallan...');
              
              await ApiService.createChallan(
                studentUserId: _selectedStudent!['id'],
                title: _challanTitleController.text.trim(),
                category: _challanCategory,
                amount: amount,
                dueDate: due,
                filePath: filePath,
                fileName: fileName,
                fileBytes: fileBytes, // Always pass bytes for web compatibility
              );
              
              print('[DEBUG] API call successful');
              
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Challan created successfully')),
                );
              }
            } catch (e) {
              print('[DEBUG] Error creating challan: $e');
              print('[DEBUG] Error type: ${e.runtimeType}');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to create challan: $e')),
                );
              }
            } finally {
              if (mounted) setState(() => modalSaving = false);
            }
          }

          return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : lightCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: isDark ? const Color(0xFF334155) : lightBorder, width: 1.2),
          ),
          title: Text(
            'Create Challan',
            style: GoogleFonts.inter(
              color: isDark ? Colors.white : accentBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Form(
            key: _challanFormKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _challanTitleController,
                    style: TextStyle(color: isDark ? Colors.white : accentBlue),
                    decoration: InputDecoration(
                      labelText: 'Title *',
                      labelStyle: TextStyle(color: labelColor),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: borderColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: focusedBorderColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: fieldFill,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter title' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _challanAmountController,
                          style: TextStyle(color: isDark ? Colors.white : accentBlue),
                          decoration: InputDecoration(
                            labelText: 'Amount *',
                            labelStyle: TextStyle(color: labelColor),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: borderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: focusedBorderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixText: '₹',
                            suffixStyle: TextStyle(color: isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.8)),
                            filled: true,
                            fillColor: fieldFill,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Enter amount';
                            final amount = double.tryParse(value);
                            if (amount == null || amount <= 0) return 'Enter valid amount';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _challanCategory,
                          items: const [
                            DropdownMenuItem(value: 'fee', child: Text('Fee')),
                            DropdownMenuItem(value: 'fine', child: Text('Fine')),
                            DropdownMenuItem(value: 'other', child: Text('Other')),
                          ],
                          onChanged: (v) => setState(() => _challanCategory = v ?? 'fee'),
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(color: isDark ? Colors.white : accentBlue),
                          decoration: InputDecoration(
                            labelText: 'Category',
                            labelStyle: TextStyle(color: labelColor),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: borderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: focusedBorderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: fieldFill,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDueDate(setState),
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            _challanDueDate == null
                                ? 'Pick Due Date'
                                : '${_challanDueDate!.day}/${_challanDueDate!.month}/${_challanDueDate!.year}',
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: borderColor),
                            foregroundColor: isDark ? Colors.white : accentBlue,
                            backgroundColor: isDark ? Colors.transparent : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickChallanFile(setState),
                          icon: const Icon(Icons.attach_file),
                          label: Text(_selectedChallanFileName ?? 'Choose File'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: borderColor),
                            foregroundColor: isDark ? Colors.white : accentBlue,
                            backgroundColor: isDark ? Colors.transparent : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _uploadChallanFile(setState),
                        icon: const Icon(Icons.cloud_upload, size: 18),
                        label: const Text('Upload'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E40AF),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: modalSaving ? null : () => saveChallan(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E40AF)),
              child: modalSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('SAVE'),
            ),
          ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isHighlighted = false}) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    const accentBlue = Color(0xFF1E3A8A);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white.withValues(alpha: 0.85) : accentBlue.withValues(alpha: 0.85),
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: isDark
                    ? (isHighlighted ? Colors.white : Colors.white.withValues(alpha: 0.75))
                    : (isHighlighted ? accentBlue : accentBlue.withValues(alpha: 0.7)),
                fontSize: 14,
                fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  final _paymentFormKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _paymentMethodController = TextEditingController();
  final _notesController = TextEditingController();
  final _linkController = TextEditingController();
  bool _isProcessingPayment = false;
  String? _selectedFileName;

  // Challan (design-only in Step 2)
  final _challanFormKey = GlobalKey<FormState>();
  final _challanTitleController = TextEditingController();
  final _challanAmountController = TextEditingController();
  String _challanCategory = 'fee'; // fee | fine | other
  DateTime? _challanDueDate;
  String? _selectedChallanFileName;
  PlatformFile? _challanPickedFile;
  final List<Map<String, dynamic>> _studentChallans = []; // populated in Step 3

  @override
  void dispose() {
    _typeAheadController.dispose();
    _amountController.dispose();
    _paymentMethodController.dispose();
    _notesController.dispose();
    _linkController.dispose();
    _challanTitleController.dispose();
    _challanAmountController.dispose();
    super.dispose();
  }

  Future<void> _pickFile(StateSetter setState) async {
    try {
      // Placeholder for file picker implementation
      // In a real implementation, you would use file_picker package
      // For now, we'll simulate file selection
      setState(() {
        _selectedFileName = 'payment_receipt.pdf';
      });
      
      // Show feedback to user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File selected successfully'),
          backgroundColor: Color(0xFF059669),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting file: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _processPayment() async {
    if (!_paymentFormKey.currentState!.validate()) return;

    setState(() => _isProcessingPayment = true);

    try {
      final amount = double.tryParse(_amountController.text) ?? 0;
      
      await ApiService.recordPayment(
        studentId: _selectedStudent!['id'],
        amount: amount,
        paymentMethod: _paymentMethodController.text,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded successfully'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Refresh student data
        _searchStudent(_selectedStudent!['name']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }
  
  bool _isLoadingPaymentHistory = false;
  String? _paymentHistoryError;
  List<Map<String, dynamic>> _paymentHistory = [];

  Future<void> _loadPaymentHistory() async {
    if (_selectedStudent == null) return;

    final dynamic rawId = _selectedStudent!['id'];
    final int? studentId = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '');
    if (studentId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load payment history: invalid student id.')),
        );
      }
      return;
    }

    setState(() {
      _isLoadingPaymentHistory = true;
      _paymentHistoryError = null;
    });

    try {
      final history = await ApiService.getPaymentHistory(studentId);
      setState(() {
        _paymentHistory = history;
        _paymentHistoryError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _paymentHistoryError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPaymentHistory = false);
      }
    }
  }

  void _showPaymentHistory() {
    _paymentHistory = [];
    _isLoadingPaymentHistory = true;
    _loadPaymentHistory();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          const Color accentBlue = Color(0xFF1E3A8A);
          const Color lightCard = Color(0xFFE7E0DE);
          const Color lightBorder = Color(0xFFD9D2D0);
          final Color secondaryText = isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.75);

          double parseAmount(dynamic raw) {
            if (raw is num) return raw.toDouble();
            return double.tryParse(raw?.toString() ?? '') ?? 0;
          }

          String readString(dynamic raw) => raw?.toString() ?? 'N/A';

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : lightCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: isDark ? const Color(0xFF334155) : lightBorder),
            ),
            title: Text(
              'Payment History',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : accentBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Container(
              width: 520,
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.95,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: _isLoadingPaymentHistory
                  ? const Center(child: CircularProgressIndicator())
                  : (_paymentHistoryError != null)
                      ? Center(
                          child: Text(
                            'Failed to load payment history:\n$_paymentHistoryError',
                            style: GoogleFonts.inter(color: secondaryText),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _paymentHistory.isEmpty
                          ? Text(
                              'No payment history found',
                              style: GoogleFonts.inter(color: secondaryText),
                              textAlign: TextAlign.center,
                            )
                      : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final payment in _paymentHistory)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : lightBorder,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '₹${parseAmount(payment['amount']).toStringAsFixed(2)}',
                                            style: GoogleFonts.inter(
                                              color: isDark ? Colors.white : accentBlue,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? const Color(0xFF1E40AF).withValues(alpha: 0.2)
                                                  : accentBlue.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: isDark
                                                    ? const Color(0xFF1E40AF)
                                                    : accentBlue.withValues(alpha: 0.75),
                                              ),
                                            ),
                                            child: Text(
                                              readString(payment['payment_method']),
                                              style: GoogleFonts.inter(
                                                color: isDark ? const Color(0xFF93C5FD) : accentBlue,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatDate(readString(payment['payment_date'])),
                                        style: GoogleFonts.inter(color: secondaryText, fontSize: 12),
                                      ),
                                      if ((payment['notes']?.toString().trim().isNotEmpty ?? false)) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          payment['notes'].toString(),
                                          style: GoogleFonts.inter(
                                            color: secondaryText,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close'.toUpperCase(),
                  style: GoogleFonts.inter(color: secondaryText, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${_getDayName(date.weekday)}, ${date.day} ${_getMonthName(date.month)} ${date.year}';
    } catch (e) {
      return dateString;
    }
  }
  
  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
  
  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  void _showVerifyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        bool hasDownloaded = false;
        String? proofFileName;
        bool isLoadingProof = true;
        bool loadedOnce = false;
        int? pickedChallanId;
        bool isVerifying = false;

        String proofUrlFor(String name) {
          final base = ApiService.baseUrl; // e.g., http://localhost/backend/api.php
          final idx = base.lastIndexOf('/');
          final root = idx != -1 ? base.substring(0, idx) : base; // http://localhost/backend
          return '$root/uploads/challans/proofs/$name';
        }

        Future<void> loadProof(StateSetter setSBState) async {
          if (_selectedStudent == null) {
            setSBState(() {
              isLoadingProof = false;
              proofFileName = null;
            });
            return;
          }
          try {
            final res = await ApiService.listChallans(studentId: _selectedStudent!['id']);
            // Debug preview
            try {
              final preview = res.toString();
              // ignore: avoid_print
              print('[VerifyDialog] listChallans response preview: ${preview.length > 400 ? '${preview.substring(0,400)}...' : preview}');
            } catch (_) {}
            final List challans = (res['challans'] ?? []) as List;
            Map<String, dynamic>? picked;
            // 1) Prefer challans that are awaiting verification (status processing/pending_verification)
            for (final c in challans) {
              final m = Map<String, dynamic>.from(c as Map);
              final pf = m['proof_file_name']?.toString();
              final st = (m['status'] ?? '').toString().toLowerCase();
              if (pf != null && pf.isNotEmpty && (st == 'processing' || st == 'pending_verification')) {
                picked = m; break;
              }
            }
            // 2) Fallback: any challan with a proof file
            if (picked == null) {
              for (final c in challans) {
                final m = Map<String, dynamic>.from(c as Map);
                final pf = m['proof_file_name']?.toString();
                if (pf != null && pf.isNotEmpty) { picked = m; break; }
              }
            }
            setSBState(() {
              proofFileName = picked?['proof_file_name'] as String?;
              isLoadingProof = false;
              final dynamic rawId = picked?['id'] ?? picked?['challan_id'] ?? picked?['challanId'];
              if (rawId is int) {
                pickedChallanId = rawId;
              } else if (rawId is String) pickedChallanId = int.tryParse(rawId);
            });
            if (proofFileName == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No payment proof found for this student')),
              );
            }
          } catch (e) {
            setSBState(() {
              isLoadingProof = false;
              proofFileName = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to load proof: $e')),
            );
          }
        }

        Future<void> verify(StateSetter setSBState) async {
          if (pickedChallanId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cannot verify: challan id not found')),
            );
            return;
          }
          try {
            setSBState(() => isVerifying = true);
            final res = await ApiService.verifyChallan(
              challanId: pickedChallanId!,
              action: 'verify',
            );
            if ((res['success'] ?? false) == true) {
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Challan verified successfully')),
                );
                // Refresh outer view if a student is selected
                if (_selectedStudent != null) {
                  // ignore: use_build_context_synchronously
                  _searchStudent(_selectedStudent!['name'] ?? '');
                }
              }
            } else {
              throw Exception(res['error'] ?? 'Verification failed');
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to verify challan: $e')),
            );
          } finally {
            setSBState(() => isVerifying = false);
          }
        }

        Future<void> openProof(StateSetter setSBState) async {
          if (proofFileName == null) return;
          final url = Uri.parse(proofUrlFor(proofFileName!));
          try {
            if (await canLaunchUrl(url)) {
              final ok = await launchUrl(url, mode: LaunchMode.platformDefault);
              if (ok) {
                setSBState(() => hasDownloaded = true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to open proof file')),
                );
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Cannot launch URL: $url')),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error opening proof: $e')),
            );
          }
        }

        return StatefulBuilder(
          builder: (context, setSBState) {
            if (!loadedOnce) {
              loadedOnce = true;
              Future.microtask(() => loadProof(setSBState));
            }

            final bool isDark = Theme.of(context).brightness == Brightness.dark;
            const Color accentBlue = Color(0xFF1E3A8A);
            const Color lightCard = Color(0xFFE7E0DE);
            const Color lightBorder = Color(0xFFD9D2D0);
            final Color secondaryText = isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.75);
            final Color openBorderColor = proofFileName == null
                ? (isDark ? Colors.white24 : lightBorder)
                : (isDark ? Colors.white.withValues(alpha: 0.35) : accentBlue.withValues(alpha: 0.7));
            final Color openFgColor = proofFileName == null
                ? (isDark ? Colors.white54 : accentBlue.withValues(alpha: 0.5))
                : (isDark ? Colors.white : accentBlue);

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : lightCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isDark ? const Color(0xFF334155) : lightBorder),
              ),
              title: Text(
                'Verify Payment',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : accentBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please review the uploaded payment proof before verifying.',
                    style: GoogleFonts.inter(color: secondaryText),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : lightBorder,
                      ),
                    ),
                    child: isLoadingProof
                        ? const SizedBox(
                            height: 48,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E40AF).withValues(alpha: 0.2)
                                      : accentBlue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF1E40AF)
                                        : accentBlue.withValues(alpha: 0.8),
                                  ),
                                ),
                                child: Icon(
                                  Icons.description,
                                  color: isDark ? const Color(0xFF93C5FD) : accentBlue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      proofFileName ?? 'No payment proof found',
                                      style: GoogleFonts.inter(
                                        color: isDark ? Colors.white : accentBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      proofFileName == null
                                          ? 'The student has not uploaded any proof yet.'
                                          : 'Tap Open to review the uploaded proof.',
                                      style: GoogleFonts.inter(color: secondaryText, fontSize: 12),
                                    ),
                                    if (proofFileName != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        proofUrlFor(proofFileName!),
                                        style: GoogleFonts.inter(
                                          color: isDark ? Colors.white24 : accentBlue.withValues(alpha: 0.4),
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ]
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: proofFileName == null ? null : () => openProof(setSBState),
                                icon: Icon(Icons.open_in_new, color: openFgColor),
                                label: Text(
                                  'Open',
                                  style: GoogleFonts.inter(
                                    color: openFgColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: openBorderColor),
                                  foregroundColor: openFgColor,
                                  backgroundColor: isDark ? Colors.transparent : Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: (proofFileName != null && hasDownloaded && !isVerifying) ? () => verify(setSBState) : null,
                                icon: const Icon(Icons.verified),
                                label: isVerifying
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text(
                                        'Verify',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF009E67),
                                  disabledBackgroundColor: isDark
                                      ? const Color(0xFF1F2937)
                                      : const Color(0xFF009E67).withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(color: secondaryText),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  void _showPaymentDialog() {
    _amountController.clear();
    _paymentMethodController.clear();
    _notesController.clear();
    _linkController.clear();
    _selectedFileName = null;
    _isProcessingPayment = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'Record Payment',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          content: Form(
            key: _paymentFormKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _amountController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Amount *',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFF1E40AF)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixText: '₹',
                      suffixStyle: const TextStyle(color: Colors.white70),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an amount';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),
            
                 
                  const SizedBox(height: 20),
                  
                  // Attachments Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.attach_file, color: Color(0xFF1E3A8A), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Payment Attachments',
                              style: GoogleFonts.inter(
                                color: Colors.black87,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Link Input Field
                        TextFormField(
                          controller: _linkController,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Payment Link (Optional)',
                            labelStyle: const TextStyle(color: Colors.black54),
                            hintText: 'Enter payment receipt link or transaction URL',
                            hintStyle: const TextStyle(color: Colors.black45),
                            prefixIcon: const Icon(Icons.link, color: Color(0xFF1E3A8A)),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Color(0xFF1E3A8A)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // File Upload Button
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedFileName != null 
                                  ? const Color(0xFF059669) 
                                  : const Color(0xFF334155),
                              width: 2,
                            ),
                            color: _selectedFileName != null 
                                ? const Color(0xFF059669).withValues(alpha: 0.1)
                                : const Color(0xFF1E293B),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _pickFile(setState),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Icon(
                                      _selectedFileName != null 
                                          ? Icons.check_circle 
                                          : Icons.cloud_upload_outlined,
                                      color: _selectedFileName != null 
                                          ? const Color(0xFF059669) 
                                          : const Color(0xFF3B82F6),
                                      size: 32,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _selectedFileName ?? 'Upload Payment Receipt',
                                      style: GoogleFonts.inter(
                                        color: _selectedFileName != null 
                                            ? const Color(0xFF059669) 
                                            : Colors.white70,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (_selectedFileName == null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'PDF, JPG, PNG files supported',
                                        style: GoogleFonts.inter(
                                          color: Colors.white38,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isProcessingPayment ? null : () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: _isProcessingPayment ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E40AF),
                disabledBackgroundColor: Colors.blueGrey[700],
              ),
              child: _isProcessingPayment
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('RECORD PAYMENT'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDesktop = MediaQuery.of(context).size.width >= 768;
    final bool isDark = theme.brightness == Brightness.dark;
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop
          ? AppBar(
            // Only show back button on desktop devices (768px and above)
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () async {
                final popped = await Navigator.of(context).maybePop();
                if (!popped && context.mounted) {
                  Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const StudentDashboard()),
                  );
                }
              },
            ),
            automaticallyImplyLeading: true,
            title: Text(
              'Admin Dues',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: primaryBlue,
            elevation: 0,
            centerTitle: true,
          )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : lightCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.12) : lightBorder,
                ),
                boxShadow: isDark
                    ? const []
                    : [
                        BoxShadow(
                          color: primaryBlue.withValues(alpha: 0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _showFiltersDialog,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: primaryBlue),
                          foregroundColor: primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        icon: const Icon(Icons.filter_list, color: primaryBlue, size: 18),
                        label: Text(
                          'Filters',
                          style: GoogleFonts.inter(color: primaryBlue, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TypeAheadField<Map<String, dynamic>>(
                    controller: _typeAheadController,
                    builder: (context, controller, focusNode) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: _searchType == 'name' ? 'Search by name...' : 'Search by roll number...',
                          hintStyle: const TextStyle(color: Colors.black45),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          prefixIcon: const Icon(Icons.search, color: Colors.black45),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.black45, size: 20),
                                  onPressed: () {
                                    controller.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) => setState(() {}),
                      );
                    },
                    suggestionsCallback: (pattern) async {
                      if (pattern.length < 2) return [];
                      final results = await _fetchStudents(pattern);
                      if (_selectedClassFilter == null || _selectedClassFilter!.isEmpty) {
                        return results;
                      }
                      final classFilterLower = _selectedClassFilter!.toLowerCase();
                      return results.where((s) {
                        final c1 = s['class']?.toString();
                        final c2 = s['class_name']?.toString();
                        final cls = (c1 ?? c2)?.toLowerCase();
                        return cls != null && cls.contains(classFilterLower);
                      }).toList();
                    },
                    itemBuilder: (context, suggestion) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: primaryBlue,
                          child: Text(
                            suggestion['name']?.toString().substring(0, 1).toUpperCase() ?? '?',
                            style: GoogleFonts.inter(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          suggestion['name']?.toString() ?? 'Unknown',
                          style: const TextStyle(color: Colors.black87),
                        ),
                        subtitle: Text(
                          'Roll: ${suggestion['roll_number'] ?? 'N/A'} | Class: ${suggestion['class'] ?? suggestion['class_name'] ?? 'N/A'}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      );
                    },
                    onSelected: (suggestion) {
                      setState(() {
                        _selectedStudent = suggestion;
                        _saveRecentSearch(suggestion);
                        // Student details will now show directly on main screen
                      });
                    },
                    emptyBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Text('No students found', style: TextStyle(color: Colors.black54)),
                    ),
                    loadingBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        height: 50,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _typeAheadController.text.trim().isEmpty 
                          ? null 
                          : () => _searchStudent(_typeAheadController.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Search Student',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Recent Searches',
                    style: GoogleFonts.inter(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : primaryBlue.withValues(alpha: 0.75),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Student Details Section
            if (_selectedStudent != null) _buildStudentDetailsCard(),
          ],
          ),
        ),
      ),
    );
  }
}
