import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/native_ad_widget.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_animate/flutter_animate.dart';

class PostList extends StatelessWidget {
  final FirestoreService firestore;
  final String searchQuery;
  final bool isAdFree;
  final List<NativeAd?> nativeAds;
  final bool isNativeAdsLoading;
  final Function(String) onPostTap;
  final Function(String) onProfileTap;

  const PostList({
    super.key,
    required this.firestore,
    required this.searchQuery,
    required this.isAdFree,
    required this.nativeAds,
    required this.isNativeAdsLoading,
    required this.onPostTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('posts').orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        print('Stream snapshot state: ${snapshot.connectionState}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print('Stream error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: ${snapshot.error}', style: Theme.of(context).textTheme.bodyLarge),
                ElevatedButton(
                  onPressed: () => (context as Element).markNeedsBuild(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          print('No data in snapshot');
          return Center(child: Text('No posts found', style: Theme.of(context).textTheme.bodyLarge));
        }

        var posts = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return (data['content']?.toString().toLowerCase().contains(searchQuery) ?? false) ||
              (data['posterName']?.toString().toLowerCase().contains(searchQuery) ?? false);
        }).toList();

        List<Widget> listItems = [];
        for (int i = 0; i < posts.length; i++) {
          var post = posts[i];
          var data = post.data() as Map<String, dynamic>;
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
          final timeAgo = timestamp != null ? timeago.format(timestamp) : 'Just now';
          final content = data['content'] as String? ?? '';
          final mediaUrls = data['mediaUrls'] as List<dynamic>? ?? [];
          final isLongContent = content.length > 250;
          final previewContent = isLongContent ? '${content.substring(0, 250)}...' : content;

          listItems.add(
            GestureDetector(
              onTap: () => onPostTap(post.id),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, data, timeAgo),
                      const SizedBox(height: 12),
                      if (previewContent.isNotEmpty) ...[
                        Text(
                          previewContent,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (isLongContent)
                          GestureDetector(
                            onTap: () => onPostTap(post.id),
                            child: Text(
                              'See more',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFFF6200)),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (mediaUrls.isNotEmpty)
                        mediaUrls.length == 1
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: mediaUrls.first,
                                  width: screenWidth - 24,
                                  height: (screenWidth - 24) * 0.75,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    width: screenWidth - 24,
                                    height: (screenWidth - 24) * 0.75,
                                    color: Colors.grey[200],
                                    child: const Center(child: CircularProgressIndicator()),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: screenWidth - 24,
                                    height: (screenWidth - 24) * 0.75,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.error, color: Colors.red),
                                  ),
                                ),
                              )
                            : CarouselSlider(
                                options: CarouselOptions(
                                  height: (screenWidth - 24) * 0.75,
                                  viewportFraction: 1.0,
                                  enableInfiniteScroll: false,
                                  padEnds: false,
                                ),
                                items: mediaUrls.map((url) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: url,
                                      width: screenWidth - 24,
                                      height: (screenWidth - 24) * 0.75,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        width: screenWidth - 24,
                                        height: (screenWidth - 24) * 0.75,
                                        color: Colors.grey[200],
                                        child: const Center(child: CircularProgressIndicator()),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        width: screenWidth - 24,
                                        height: (screenWidth - 24) * 0.75,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.error, color: Colors.red),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                      const SizedBox(height: 12),
                      _buildFooter(context, data, post.id),
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(duration: const Duration(milliseconds: 500), delay: Duration(milliseconds: 100 * i)),
          );

          if (!isAdFree && (i + 1) % 5 == 0) {
            final adIndex = (i + 1) ~/ 5 - 1;
            if (adIndex < nativeAds.length && nativeAds[adIndex] != null) {
              listItems.add(
                Semantics(
                  label: 'Advertisement',
                  child: NativeAdWidget(ad: nativeAds[adIndex]!).animate().fadeIn(
                        duration: const Duration(milliseconds: 400),
                        delay: Duration(milliseconds: 100 * (i + 1)),
                      ),
                ),
              );
            } else if (isNativeAdsLoading) {
              listItems.add(
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              );
            }
          }
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: listItems,
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Map<String, dynamic> data, String timeAgo) {
    return GestureDetector(
      onTap: () => onProfileTap(data['posterId']),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: data['posterProfilePicUrl'] != null ? NetworkImage(data['posterProfilePicUrl']) : null,
            child: data['posterProfilePicUrl'] == null ? const Icon(Icons.person, size: 20) : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data['posterName'] ?? 'Anonymous',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            timeAgo,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, Map<String, dynamic> data, String postId) {
    return Row(
      children: [
        Icon(Icons.favorite_border, size: 24, color: const Color(0xFFFF6200))
            .animate()
            .scale(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut),
        const SizedBox(width: 4),
        Text(
          '${data['likeCount'] ?? 0}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(width: 16),
        Icon(Icons.chat_bubble_outline, size: 24, color: const Color(0xFFFF6200)),
        const SizedBox(width: 4),
        StreamBuilder<QuerySnapshot>(
          stream: firestore.getComments(postId),
          builder: (context, snapshot) {
            return Text(
              '${snapshot.data?.docs.length ?? 0}',
              style: Theme.of(context).textTheme.bodyMedium,
            );
          },
        ),
      ],
    );
  }
}