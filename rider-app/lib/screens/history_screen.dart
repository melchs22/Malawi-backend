import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getMyRequests();
    if (mounted) {
      setState(() {
        requests = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF10223D),
        title: const Text(
          "Assist History",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            "No assist history found",
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final req = requests[index];
                        return _buildRequestCard(req);
                      },
                    ),
            ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final status = req['status'] ?? 'UNKNOWN';
    final color = _getStatusColor(status);
    final serviceType = req['service_type_name'] ?? "Service";
    final dateTimeStr = req['created_at'] ?? '';
    final jobId = req['id']?.toString() ?? '';
    final rodieUsername = req['rodie_username'] ?? 'Searching...';

    // Format date and time (Uganda Time Zone: UTC+3)
    String formattedDateTime = '';
    if (dateTimeStr.isNotEmpty) {
      try {
        final date = DateTime.parse(dateTimeStr).toUtc().add(const Duration(hours: 3));
        formattedDateTime = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        formattedDateTime = dateTimeStr.split('T')[0] ?? dateTimeStr;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    serviceType,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: Color(0xFF10223D),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.calendar_today_outlined, 'Date', formattedDateTime),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.tag_outlined, 'Job ID', '#$jobId'),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.person_outline, 'Mechanic', rodieUsername),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF10223D),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.green.shade700;
      case 'CANCELLED':
        return Colors.red.shade700;
      case 'REQUESTED':
        return Colors.orange.shade800;
      case 'ACCEPTED':
      case 'EN_ROUTE':
      case 'STARTED':
        return const Color(0xFF10223D);
      default:
        return Colors.grey.shade600;
    }
  }
}
