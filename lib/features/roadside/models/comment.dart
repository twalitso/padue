import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String commenterId;
  final String commenterName;
  final String text;
  final DateTime? timestamp;

  Comment({
    required this.id,
    required this.commenterId,
    required this.commenterName,
    required this.text,
    this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'commenterId': commenterId,
        'commenterName': commenterName,
        'text': text,
        'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : null,
      };

  factory Comment.fromMap(Map<String, dynamic> data, String id) => Comment(
        id: id,
        commenterId: data['commenterId'] as String,
        commenterName: data['commenterName'] as String,
        text: data['text'] as String,
        timestamp: data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate() : null,
      );
}