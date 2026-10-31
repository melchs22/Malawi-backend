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
      appBar: AppBar(title: const Text("Job History")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: requests.isEmpty
                  ? const Center(child: Text("No history"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
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
    final dateTime = req['created_at'] ?? '';
    final jobId = req['id']?.toString() ?? '';
    final riderUsername = req['rider_username'] ?? 'Unknown';

    // Format date and time (Uganda Time Zone: UTC+3)
    String formattedDateTime = '';
    if (dateTime.isNotEmpty) {
      try {
        final date = DateTime.parse(dateTime).toUtc().add(const Duration(hours: 3));
        formattedDateTime = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        formattedDateTime = dateTime.split('T')[0] ?? dateTime;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      fontSize: 18,
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
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.access_time, 'Date/Time', formattedDateTime),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.tag, 'Job ID', '#$jobId'),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.person, 'Driver', riderUsername),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
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
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.red;
      case 'REQUESTED':
        return Colors.orange;
      case 'ACCEPTED':
      case 'EN_ROUTE':
      case 'STARTED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
