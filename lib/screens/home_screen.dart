import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _barNameController = TextEditingController();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Local map to track optimistic updates
  final Map<String, Map<String, int>> _localVotes = {};

  Future<void> _addHappyHour() async {
    if (_barNameController.text.isNotEmpty &&
        _startTime != null &&
        _endTime != null) {
      await _firestore.collection('happy_hours').add({
        'bar_name': _barNameController.text.trim(),
        'start_time': _startTime!.format(context),
        'end_time': _endTime!.format(context),
        'upvotes': 0,
        'downvotes': 0,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _barNameController.clear();
      _startTime = null;
      _endTime = null;
      setState(() {});
    }
  }

  void _updateVotesOptimistically(String docId, bool isUpvote) {
    // Optimistically update local votes
    setState(() {
      _localVotes[docId] ??= {'upvotes': 0, 'downvotes': 0};
      if (isUpvote) {
        _localVotes[docId]!['upvotes'] =
            (_localVotes[docId]!['upvotes'] ?? 0) + 1;
      } else {
        _localVotes[docId]!['downvotes'] =
            (_localVotes[docId]!['downvotes'] ?? 0) + 1;
      }
    });

    // Update Firestore
    final document = _firestore.collection('happy_hours').doc(docId);
    document.update({
      'upvotes': FieldValue.increment(isUpvote ? 1 : 0),
      'downvotes': FieldValue.increment(!isUpvote ? 1 : 0),
    }).catchError((error) {
      // Rollback local votes on failure
      setState(() {
        if (isUpvote) {
          _localVotes[docId]!['upvotes'] =
              (_localVotes[docId]!['upvotes'] ?? 0) - 1;
        } else {
          _localVotes[docId]!['downvotes'] =
              (_localVotes[docId]!['downvotes'] ?? 0) - 1;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find My Happy Hour'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _barNameController,
              decoration: InputDecoration(
                labelText: 'Bar Name',
                prefixIcon: const Icon(Icons.local_bar, color: Colors.orange),
                filled: true,
                fillColor: Colors.white.withOpacity(0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.9),
                      foregroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _startTime ??
                            TimeOfDay(
                                hour: 17, minute: 0), // Default to 5:00 PM
                        helpText: 'Select Start Time',
                      );
                      setState(() => _startTime = time);
                    },
                    child: Text(
                      _startTime != null
                          ? 'Start: ${_startTime!.format(context)}'
                          : 'Select Start Time',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.9),
                      foregroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _endTime ??
                            TimeOfDay(
                                hour: 18, minute: 0), // Default to 6:00 PM
                        helpText: 'Select End Time',
                      );
                      setState(() => _endTime = time);
                    },
                    child: Text(
                      _endTime != null
                          ? 'End: ${_endTime!.format(context)}'
                          : 'Select End Time',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _addHappyHour,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Add Happy Hour'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('happy_hours')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.orange),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                final data = snapshot.data?.docs ?? [];
                if (data.isEmpty) {
                  return const Center(
                    child: Text(
                      'No Happy Hours Found!',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final bar = data[index];
                    final docId = bar.id;

                    // Combine Firestore and local votes
                    final localUpvotes = _localVotes[docId]?['upvotes'] ?? 0;
                    final localDownvotes =
                        _localVotes[docId]?['downvotes'] ?? 0;
                    final upvotes = (bar['upvotes'] ?? 0) + localUpvotes;
                    final downvotes = (bar['downvotes'] ?? 0) + localDownvotes;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.local_bar,
                          color: Colors.orange,
                        ),
                        title: Text(
                          bar['bar_name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                            'Happy Hour: ${bar['start_time']} - ${bar['end_time']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.thumb_up,
                                  color: Colors.green),
                              onPressed: () =>
                                  _updateVotesOptimistically(docId, true),
                            ),
                            Text('$upvotes'),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.thumb_down,
                                  color: Colors.red),
                              onPressed: () =>
                                  _updateVotesOptimistically(docId, false),
                            ),
                            Text('$downvotes'),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
