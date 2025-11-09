import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/responsive_helper.dart';
import '../services/api_service.dart';
import 'home.dart';

class Due {
  final String title;
  final String description;
  final double amount;
  final DateTime dueDate;
  final String status;
  final String category;
  final String? challanId;
  final String? filePath;
  final String? paymentProofPath;

  Due({
    required this.title,
    required this.description,
    required this.amount,
    required this.dueDate,
    required this.status,
    required this.category,
    this.challanId,
    this.filePath,
    this.paymentProofPath,
  });
}

class DuesScreen extends StatefulWidget {
  const DuesScreen({super.key});

  @override
  State<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends State<DuesScreen> {
  List<Due> _dues = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _downloadedChallans = {}; // Track which challans have been downloaded

  @override
  void initState() {
    super.initState();
    _loadChallans();
  }

  Future<void> _loadChallans() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      
      final response = await ApiService.listChallans();
      
      if (response['success'] == true && 
          response['challans'] is List) {
        
        setState(() {
          if (kDebugMode) debugPrint('DEBUG: Raw challans response: ${response['challans']}');
          _dues = (response['challans'] as List).map((challan) {
            if (kDebugMode) debugPrint('DEBUG: Processing challan: $challan');
            // Parse due date
            DateTime? dueDate;
            if (challan['due_date'] != null) {
              try {
                dueDate = DateTime.parse(challan['due_date']);
              } catch (e) {
                dueDate = DateTime.now().add(const Duration(days: 30));
              }
            } else {
              dueDate = DateTime.now().add(const Duration(days: 30));
            }
            
            // Determine status from backend 'status' field
            final rawStatus = (challan['status'] ?? '').toString().toLowerCase();
            String status;
            if (rawStatus == 'verified') {
              status = 'verified';
            } else if (rawStatus == 'processing' || rawStatus == 'to_verify' || rawStatus == 'pending_verification') {
              status = 'processing';
            } else if (rawStatus == 'overdue') {
              status = 'overdue';
            } else {
              // unpaid or unknown -> compute overdue fallback
              status = dueDate.isBefore(DateTime.now()) ? 'overdue' : 'unpaid';
            }
            
            return Due(
              title: challan['title'] ?? 'Challan',
              description: 'Category: ${challan['category'] ?? 'General'}',
              amount: double.tryParse(challan['amount']?.toString() ?? '0') ?? 0.0,
              dueDate: dueDate,
              status: status,
              category: challan['category'] ?? 'general',
              challanId: challan['id']?.toString(),
              filePath: challan['challan_file_name']?.toString(),
              paymentProofPath: challan['proof_file_name']?.toString(),
            );
          }).toList();
          // Sort: show non-verified items on top, verified at the bottom.
          _dues.sort((a, b) {
            final wa = a.status == 'verified' ? 1 : 0;
            final wb = b.status == 'verified' ? 1 : 0;
            final cmp = wa.compareTo(wb);
            if (cmp != 0) return cmp;
            // Keep backend order within groups (backend is already DESC by created_at)
            return 0;
          });
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = (response['error'] as String?) ?? 'Failed to load challans';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading challans: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final bool isMobile = ResponsiveHelper.isMobile(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          if (!isMobile)
            // Blue header bar
            Container(
              height: 64,
              width: double.infinity,
              color: primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const StudentDashboard()),
                      );
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Dues & Fees',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          if (!isMobile) const SizedBox(height: 12),
          // Body
          Expanded(child: _buildDuesBody()),
        ],
      ),
    );
  }

  Widget _buildDuesBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFEF4444),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadChallans,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final totalDues = _dues.where((due) => due.status == 'unpaid' || due.status == 'overdue' || due.status == 'processing').fold(0.0, (sum, due) => sum + due.amount);
    final overdueDues = _dues.where((due) => due.status == 'overdue').length;
    final pendingDues = _dues.where((due) => due.status == 'unpaid' || due.status == 'processing').length;

    return RefreshIndicator(
      onRefresh: _loadChallans,
      color: const Color(0xFFEF4444),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, ResponsiveHelper.isMobile(context) ? 12 : 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Cards - Responsive Layout
            ResponsiveHelper.isMobile(context)
                ? Column(
                    children: [
                      _buildSummaryCard(
                        'Total Outstanding',
                        'Rs. ${totalDues.toStringAsFixed(0)}',
                        const Color(0xFFEF4444),
                        Icons.account_balance_wallet,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'Pending',
                              '$pendingDues items',
                              const Color(0xFFF59E0B),
                              Icons.pending,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              'Overdue',
                              '$overdueDues items',
                              const Color(0xFFDC2626),
                              Icons.warning,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Total Outstanding',
                          'Rs. ${totalDues.toStringAsFixed(0)}',
                          const Color(0xFFEF4444),
                          Icons.account_balance_wallet,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.responsiveValue(
                        context,
                        mobile: 12,
                        tablet: 16,
                        desktop: 20,
                      )),
                      Expanded(
                        child: _buildSummaryCard(
                          'Pending Dues',
                          '$pendingDues items',
                          const Color(0xFFF59E0B),
                          Icons.pending,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.responsiveValue(
                        context,
                        mobile: 12,
                        tablet: 16,
                        desktop: 20,
                      )),
                      Expanded(
                        child: _buildSummaryCard(
                          'Overdue Items',
                          '$overdueDues items',
                          const Color(0xFFDC2626),
                          Icons.warning,
                        ),
                      ),
                    ],
                  ),
            SizedBox(
              height: ResponsiveHelper.responsiveValue(
                context,
                mobile: 8,
                tablet: 12,
                desktop: 16,
              ),
            ),

            // Dues List
            if (_dues.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No dues found',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have no pending or overdue fees at the moment.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...List.generate(
                _dues.length,
                (index) => _buildDueCard(_dues[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color, IconData icon) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    const primaryBlue = Color(0xFF1E3A8A);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? lightCard : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? lightBorder : color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color, // keep semantic color (red/yellow)
                size: 24,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  title.split(' ').first,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isLight ? primaryBlue : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isLight
                  ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDueCard(Due due) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    const primaryBlue = Color(0xFF1E3A8A);
    final isOverdue = due.status == 'overdue';
    final isVerified = due.status == 'verified';
    final isProcessing = due.status == 'processing';
    // final daysUntilDue = due.dueDate.difference(DateTime.now()).inDays; // Removed unused variable
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    switch (due.status) {
      case 'verified':
        statusColor = const Color(0xFF10B981);
        statusText = 'Verified';
        statusIcon = Icons.check_circle;
        break;
      case 'processing':
        statusColor = const Color(0xFF3B82F6);
        statusText = 'Processing';
        statusIcon = Icons.hourglass_empty;
        break;
      case 'overdue':
        statusColor = const Color(0xFFDC2626);
        statusText = 'Overdue';
        statusIcon = Icons.warning;
        break;
      default: // unpaid
        statusColor = const Color(0xFFF59E0B);
        statusText = 'Unpaid';
        statusIcon = Icons.payment;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? lightBorder : statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // status stripe on top to keep red/yellow cue
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      due.title,
                      style: GoogleFonts.inter(
                        fontSize: ResponsiveHelper.getSubheadingSize(context),
                        fontWeight: FontWeight.bold,
                        color: isLight ? primaryBlue : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      due.description,
                      style: GoogleFonts.inter(
                        fontSize: ResponsiveHelper.getBodySize(context),
                        color: isLight
                            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusIcon,
                      color: statusColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ResponsiveHelper.isMobile(context)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Amount',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isLight
                                      ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                                      : Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Rs. ${due.amount.toStringAsFixed(0)}',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isLight ? primaryBlue : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Due Date',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isLight
                                      ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                                      : Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${due.dueDate.day}/${due.dueDate.month}/${due.dueDate.year}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isOverdue ? const Color(0xFFDC2626) : Colors.white,
                                ),
                              ),
                              if (isOverdue)
                                Text(
                                  '${DateTime.now().difference(due.dueDate).inDays} days overdue',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFFDC2626),
                                  ),
                                )
                              else if (!isVerified && !isProcessing)
                                Text(
                                  '${due.dueDate.difference(DateTime.now()).inDays} days left',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFFF59E0B),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Button row for Pay Now and Upload Proof
                    if (!isVerified)
                      Row(
                        children: [
                          // Pay Now button (downloads challan)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _downloadChallan(due);
                              },
                              icon: const Icon(Icons.download, size: 16),
                              label: Text(
                                'Pay Now',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Upload Proof button - only enabled after Pay Now is clicked
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (isProcessing || !_downloadedChallans.contains(due.challanId ?? '')) ? null : () {
                                _showPaymentDialog(due);
                              },
                              icon: const Icon(Icons.upload_file, size: 16),
                              label: Text(
                                isProcessing ? 'Processing' : 'Upload Proof',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: (isProcessing || !_downloadedChallans.contains(due.challanId ?? '')) 
                                  ? Colors.grey 
                                  : const Color(0xFF10B981),
                                side: BorderSide(color: (isProcessing || !_downloadedChallans.contains(due.challanId ?? '')) 
                                  ? Colors.grey 
                                  : const Color(0xFF10B981)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amount',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rs. ${due.amount.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Due Date',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${due.dueDate.day}/${due.dueDate.month}/${due.dueDate.year}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isOverdue ? const Color(0xFFDC2626) : Colors.white,
                            ),
                          ),
                          if (isOverdue)
                            Text(
                              '${DateTime.now().difference(due.dueDate).inDays} days overdue',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFFDC2626),
                              ),
                            )
                          else if (!isVerified && !isProcessing)
                            Text(
                              '${due.dueDate.difference(DateTime.now()).inDays} days left',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!isVerified) ...[
                      const SizedBox(width: 16),
                      // Pay Now button (downloads challan)
                      Expanded(
                        flex: 1,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _downloadChallan(due);
                          },
                          icon: Icon(Icons.download, size: ResponsiveHelper.responsiveValue(
                            context,
                            mobile: 14,
                            tablet: 15,
                            desktop: 16,
                          )),
                          label: Text(
                            'Pay Now',
                            style: GoogleFonts.inter(
                              fontSize: ResponsiveHelper.responsiveValue(
                                context,
                                mobile: 12,
                                tablet: 13,
                                desktop: 14,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Upload Proof button - only enabled after Pay Now is clicked
                      Expanded(
                        flex: 1,
                        child: OutlinedButton.icon(
                          onPressed: (isProcessing || !_downloadedChallans.contains(due.challanId ?? '')) ? null : () {
                            _showPaymentDialog(due);
                          },
                          icon: Icon(Icons.upload_file, size: ResponsiveHelper.responsiveValue(
                            context,
                            mobile: 14,
                            tablet: 15,
                            desktop: 16,
                          )),
                          label: Text(
                            isProcessing ? 'Processing' : 'Upload Proof',
                            style: GoogleFonts.inter(
                              fontSize: ResponsiveHelper.responsiveValue(
                                context,
                                mobile: 12,
                                tablet: 13,
                                desktop: 14,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: (isProcessing || !_downloadedChallans.contains(due.challanId ?? '')) 
                              ? Colors.grey 
                              : const Color(0xFF10B981),
                            side: BorderSide(color: (isProcessing || !_downloadedChallans.contains(due.challanId ?? '')) 
                              ? Colors.grey 
                              : const Color(0xFF10B981)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ],
      ),
    );
  }

  void _downloadChallan(Due due) async {
    if (kDebugMode) debugPrint('DEBUG: Challan ID: ${due.challanId}');
    if (kDebugMode) debugPrint('DEBUG: File Path: ${due.filePath}');
    if (kDebugMode) debugPrint('DEBUG: Full Due object: ${due.title}, ${due.category}');
    
    if (due.filePath == null || due.filePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No challan file available for challan ID: ${due.challanId}')),
      );
      return;
    }

    try {
      // Get base URL and construct download URL
      String baseUrl = ApiService.baseUrl;
      
      // Remove /backend/api.php from the end to get the root URL
      if (baseUrl.endsWith('/backend/api.php')) {
        baseUrl = baseUrl.replaceAll('/backend/api.php', '');
      } else if (baseUrl.endsWith('/api.php')) {
        baseUrl = baseUrl.replaceAll('/api.php', '');
      }
      
      // Construct the full download URL using challan_file_name
      final downloadUrl = '$baseUrl/backend/uploads/challans/${due.filePath}';
      
      if (kDebugMode) debugPrint('Attempting to download from: $downloadUrl');
      
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // Mark this challan as downloaded
        setState(() {
          _downloadedChallans.add(due.challanId ?? '');
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening challan file...'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open file: $downloadUrl')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading file: $e')),
        );
      }
    }
  }

  void _showPaymentDialog(Due due) {
    PlatformFile? selectedFile;
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Upload Payment Proof',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload payment proof for ${due.title} (Rs. ${due.amount.toStringAsFixed(0)})',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          selectedFile != null ? Icons.check_circle : Icons.upload_file,
                          color: selectedFile != null ? Colors.green : Colors.white.withValues(alpha: 0.6),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selectedFile != null 
                            ? 'Selected: ${selectedFile!.name}'
                            : 'Tap to select payment proof',
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Supported formats: PDF, JPG, PNG, DOC, DOCX',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                if (selectedFile == null)
                  ElevatedButton(
                    onPressed: isUploading ? null : () async {
                      try {
                        FilePickerResult? result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
                        );
                        
                        if (result != null) {
                          setState(() {
                            selectedFile = result.files.first;
                          });
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error selecting file: $e')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'Select File',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (selectedFile != null)
                  ElevatedButton(
                    onPressed: isUploading ? null : () async {
                      setState(() {
                        isUploading = true;
                      });
                      
                      try {
                        await ApiService.uploadPaymentProof(
                          challanId: due.challanId!,
                          filePath: selectedFile!.path,
                          fileName: selectedFile!.name,
                          fileBytes: selectedFile!.bytes,
                        );
                        
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Payment proof uploaded successfully!'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                          _loadChallans(); // Refresh the list
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Upload failed: $e'),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      } finally {
                        if (context.mounted) {
                          setState(() {
                            isUploading = false;
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                    ),
                    child: isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Upload',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
