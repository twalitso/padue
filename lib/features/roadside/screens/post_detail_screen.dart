import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/widgets/app_bar_widget.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:padue/features/roadside/screens/chat_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:google_fonts/google_fonts.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;
  final bool isProvider;

  const PostDetailScreen({super.key, required this.postId,this.isProvider = false});

  @override
  _PostDetailScreenState createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final FirestoreService _firestore = FirestoreService();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  UserProfile? _userProfile;
  Provider? _providerProfile;
  bool _isSubmittingComment = false;
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isLoading = true;
  Map<String, dynamic>? _postData;
  bool _isProvider = false;
 bool _isAdFree = false;

  bool _isProviderUser = false;
  dynamic profile;
  String? profilePicUrl;


  @override
  void initState() {
    super.initState();
    print('PostDetailScreen: initState called');
   // _loadUserData();
      _loadProfile();
    _checkLikeStatus();
    _loadPostData();
    _commentFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_commentFocusNode.hasFocus) {
      // Ensure the TextField is visible when focused
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Scrollable.ensureVisible(context, alignment: 0.9, duration: const Duration(milliseconds: 300));
      });
    }
  }

/** 
 Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);
    final providerDoc =
        await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
    if (providerDoc.exists && mounted) {
      final provider = Provider.fromFirestore(providerDoc);
      final providerProfile = await _firestore.getProviderProfile(user.uid);
      setState(() {
        _isProviderUser = true;
        _isAdFree = provider.adFree;
        _isLoading = false;
        profile = providerProfile;
        profilePicUrl = providerProfile?.profilePicUrl ?? provider.profilePicUrl;
      });
    } else {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userProfile = await _firestore.getUserProfile(user.uid);
      setState(() {
        _isProviderUser = false;
        _isAdFree = userDoc.exists ? (userDoc.data()?['adFree'] ?? false) : false;
        _isLoading = false;
        profile = userProfile;
        profilePicUrl = profile?.profilePicUrl;
      });
    }
  }
*/

 Future<void> _loadProfile() async {
   final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
  if(widget.isProvider){
    setState(() => _isLoading = true);
    final providerDoc =
        await FirebaseFirestore.instance.collection('providers').doc(user.uid).get();
    if (providerDoc.exists && mounted) {
      final provider = Provider.fromFirestore(providerDoc);
      final providerProfile = await _firestore.getProviderProfile(user.uid);
      setState(() {
        _isProviderUser = true;
        _isAdFree = provider.adFree;
        _isLoading = false;
        profile = providerProfile;
        profilePicUrl = providerProfile?.profilePicUrl ?? provider.profilePicUrl;
      });
    }

  }else{

 final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userProfile = await _firestore.getUserProfile(user.uid);
      setState(() {
        _isProviderUser = false;
        _isAdFree = userDoc.exists ? (userDoc.data()?['adFree'] ?? false) : false;
        _isLoading = false;
        profile = userProfile;
        profilePicUrl = profile?.profilePicUrl;
      });

  }  
  }




  Future<void> _loadUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        _userProfile = await _firestore.getUserProfile(user.uid);
        _providerProfile = await _firestore.getProviderProfile(user.uid);
        _isProvider = _providerProfile != null;
        if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        print('Error loading profile: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _loadPostData() async {
    try {
      var postDoc = await FirebaseFirestore.instance.collection('posts').doc(widget.postId).get();
      if (mounted && postDoc.exists) {
        setState(() {
          _postData = postDoc.data() as Map<String, dynamic>;
        });
      }
    } catch (e) {
      print('Error loading post data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading post: $e')));
      }
    }
  }

  Future<void> _checkLikeStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        var likeDoc = await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId)
            .collection('likes')
            .doc(user.uid)
            .get();
        var postDoc = await FirebaseFirestore.instance.collection('posts').doc(widget.postId).get();
        if (mounted) {
          setState(() {
            _isLiked = likeDoc.exists;
            _likeCount = (postDoc.data()?['likeCount'] ?? 0) as int;
          });
        }
      } catch (e) {
        print('Error checking like status: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error checking like status: $e')));
        }
      }
    }
  }

  Future<void> _toggleLike() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to like posts')));
      return;
    }

    var likeRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId).collection('likes').doc(user.uid);
    var postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        if (_isLiked) {
          transaction.set(likeRef, {'timestamp': FieldValue.serverTimestamp()});
          transaction.update(postRef, {'likeCount': FieldValue.increment(1)});
        } else {
          transaction.delete(likeRef);
          transaction.update(postRef, {'likeCount': FieldValue.increment(-1)});
        }
      });

      var postData = _postData ?? (await postRef.get()).data() as Map<String, dynamic>?;
      if (postData != null && postData['posterId'] != user.uid) {
        await _firestore.addNotification(
          userId: postData['posterId'],
          title: 'New Like',
          body: '${profile?.name ?? profile?.name ?? 'Someone'} liked your post',
          type: 'like',
          id: widget.postId,
        );
      }
    } catch (e) {
      print('Error liking post: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error liking post: $e')));
        setState(() {
          _isLiked = !_isLiked;
          _likeCount += _isLiked ? 1 : -1;
        });
      }
    }
  }

  Future<void> _submitComment() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || _commentController.text.trim().isEmpty || _isSubmittingComment) return;

    setState(() => _isSubmittingComment = true);

    try {
      var commentData = {
        'userId': user.uid,
        'content': _commentController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'userName': profile?.name ?? profile?.name ?? 'Anonymous',
        'profilePicUrl': profilePicUrl ,
      };

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add(commentData);

      var postData = _postData ?? (await FirebaseFirestore.instance.collection('posts').doc(widget.postId).get()).data();
      if (postData != null && postData['posterId'] != user.uid) {
        await _firestore.addNotification(
          userId: postData['posterId'],
          title: 'New Comment',
          body: '${profile?.name ?? profile?.name ?? 'Someone'} commented on your post',
          type: 'comment',
          id: widget.postId,
        );
      }

      _commentController.clear();
      _commentFocusNode.unfocus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment posted successfully')));
      }
    } catch (e) {
      print('Error posting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error posting comment: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
      }
    }
  }

  Future<void> _openOrCreateChat(String providerId, String userId) async {
    try {
      var existingChat = await FirebaseFirestore.instance
          .collection('chat_requests')
          .where('providerId', isEqualTo: providerId)
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: ['pending', 'accepted'])
          .limit(1)
          .get();

      String chatId;
      if (existingChat.docs.isNotEmpty) {
        chatId = existingChat.docs.first.id;
      } else {
         // Create new chat request
    final doc = await FirebaseFirestore.instance.collection('chat_requests').add({
      'providerId': providerId,
      'userId': userId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCount': 1, // new chat counts as 1 unread
    });
    chatId = doc.id;
    
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(requestId: chatId)),
        );
      }
    } catch (e) {
      print('Error opening chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
      }
    }
  }

@override
Widget build(BuildContext context) {
  if (_isLoading) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBarWidget(title: 'Post', isProvider: _isProviderUser),
      body: const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200))),
    );
  }

  if (_postData == null) {
    return Scaffold(body: Center(child: Text('Post not found')));
  }

  return Scaffold(
    backgroundColor: Colors.grey[50],
    appBar: AppBarWidget(
      title: 'Post',
      profilePicUrl: profilePicUrl,
      showNotifications: true,
      isProvider: _isProviderUser,
    ),
    drawer: AppBarWidget.buildDrawer(context: context, isProvider: _isProviderUser),

    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: _postData!['posterProfilePicUrl']?.isNotEmpty == true
                            ? NetworkImage(_postData!['posterProfilePicUrl'])
                            : const AssetImage('assets/default_profile.png') as ImageProvider,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _postData!['posterName'] ?? 'Anonymous',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                                ),
                                if (_postData!['isProvider'] == true)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(Icons.verified, color: Color(0xFFFF6200), size: 18),
                                  ),
                              ],
                            ),
                            Text(
                              timeago.format((_postData!['timestamp'] as Timestamp).toDate()),
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      if (_postData!['posterId'] != FirebaseAuth.instance.currentUser?.uid)
                        IconButton(
                          icon: const Icon(Icons.message_rounded, color: Color(0xFFFF6200)),
                          onPressed: () => _openOrCreateChat(_postData!['posterId'], FirebaseAuth.instance.currentUser!.uid),
                        ),
                    ],
                  ),
                ),

                // Post Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _postData!['content'] ?? '',
                    style: GoogleFonts.poppins(fontSize: 15.5, height: 1.5, color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 16),

                // Media
                if (_postData!['mediaUrls'] != null && (_postData!['mediaUrls'] as List).isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    child: _postData!['mediaUrls'].length == 1
                        ? CachedNetworkImage(
                            imageUrl: _postData!['mediaUrls'][0],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 340,
                            placeholder: (_, __) => Container(color: Colors.grey[200], child: const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))),
                          )
                        : CarouselSlider(
                            options: CarouselOptions(
                              height: 340,
                              viewportFraction: 1.0,
                              enlargeCenterPage: false,
                              enableInfiniteScroll: false,
                              autoPlay: false,
                            ),
                            items: (_postData!['mediaUrls'] as List).map<Widget>((url) {
                              return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover);
                            }).toList(),
                          ),
                  ),

                // Like + Comment Bar
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, size: 28),
                        color: _isLiked ? const Color(0xFFFF6200) : Colors.grey[700],
                        onPressed: _toggleLike,
                      ),
                      Text('$_likeCount', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 20),
                      const Icon(Icons.chat_bubble_outline, size: 26, color: Colors.grey),
                      const SizedBox(width: 8),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore.getComments(widget.postId),
                        builder: (context, snapshot) => Text(
                          '${snapshot.data?.docs.length ?? 0}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0),
          ),
        ),

        // Comments Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('Comments', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),

        // Comments List
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.getComments(widget.postId),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Be the first to comment!', style: GoogleFonts.poppins(color: Colors.grey[600])),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final comment = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                final timeAgo = timeago.format((comment['timestamp'] as Timestamp).toDate());

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundImage: comment['profilePicUrl']?.isNotEmpty == true
                            ? NetworkImage(comment['profilePicUrl'])
                            : const AssetImage('assets/default_profile.png') as ImageProvider,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(comment['userName'] ?? 'Anonymous', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                                FutureBuilder<String?>(
                                  future: _firestore.getUserRole(comment['userId']),
                                  builder: (context, snap) => snap.data == 'provider'
                                      ? const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, color: Color(0xFFFF6200), size: 14))
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(comment['content'], style: GoogleFonts.poppins(fontSize: 14.5)),
                            const SizedBox(height: 4),
                            Text(timeAgo, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: (80 * index).ms);
              }, childCount: snapshot.data!.docs.length),
            );
          },
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)), // Space for input
      ],
    ),

    // Comment Input (Fixed at bottom)
    bottomSheet: Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: GoogleFonts.poppins(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitComment(),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _isSubmittingComment ? null : _submitComment,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(color: Color(0xFFFF6200), shape: BoxShape.circle),
                  child: _isSubmittingComment
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/** 
  @override
  Widget build(BuildContext context) {
    print('PostDetailScreen: build called');
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      resizeToAvoidBottomInset: true, // Allow resizing for keyboard
      appBar: AppBarWidget(
        title: 'Post Details',
        profilePicUrl: profilePicUrl,
        showNotifications: true,
        isProvider: _isProviderUser,
        // onInterstitialAd: (callback) => callback(), // Uncomment if ads are needed
      ),
      drawer: AppBarWidget.buildDrawer(
        context: context,
        isProvider: _isProviderUser,
        // onInterstitialAd: (callback) => callback(), // Uncomment if ads are needed
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
          : _postData == null
              ? Center(child: Text('Post not found', style: Theme.of(context).textTheme.bodyLarge))
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Post Header
                            GestureDetector(
                              onTap: () async {
                                try {
                                  final role = await _firestore.getUserRole(_postData!['posterId']);
                                  if (role == 'provider') {
                                    Navigator.pushNamed(context, '/view_provider_profile',
                                        arguments: _postData!['posterId']);
                                  } else {
                                    Navigator.pushNamed(context, '/user_profile', arguments: _postData!['posterId']);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundImage: _postData!['posterProfilePicUrl'] != null &&
                                              _postData!['posterProfilePicUrl'].isNotEmpty
                                          ? NetworkImage(_postData!['posterProfilePicUrl'])
                                          : null,
                                      backgroundColor: Colors.grey[200],
                                      child: _postData!['posterProfilePicUrl'] == null ||
                                              _postData!['posterProfilePicUrl'].isEmpty
                                          ? const Icon(Icons.person, color: Colors.grey, size: 20)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                _postData!['posterName'] ?? 'Anonymous',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                              if (_postData!['isProvider'] == true)
                                                const Padding(
                                                  padding: EdgeInsets.only(left: 6),
                                                  child: Icon(Icons.verified, color: Color(0xFFFF6200), size: 16),
                                                ),
                                            ],
                                          ),
                                          Text(
                                            timeago.format(
                                                (_postData!['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now()),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: Colors.grey[600], fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_postData!['posterId'] != FirebaseAuth.instance.currentUser?.uid)
                                      IconButton(
                                        icon: const Icon(Icons.message, color: Color(0xFFFF6200), size: 24),
                                        onPressed: () => _openOrCreateChat(
                                            _postData!['posterId'], FirebaseAuth.instance.currentUser!.uid),
                                        tooltip: 'Message Poster',
                                      ),
                                  ],
                                ),
                              ),
                            ).animate().fadeIn(duration: 400.ms),
                            const SizedBox(height: 12),
                            // Post Content
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _postData!['content'] ?? '',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(fontSize: 16, height: 1.4),
                                  ),
                                  if (_postData!['mediaUrls'] != null && (_postData!['mediaUrls'] as List).isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    (_postData!['mediaUrls'] as List).length == 1
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: CachedNetworkImage(
                                              imageUrl: _postData!['mediaUrls'][0],
                                              width: screenWidth - 32,
                                              height: (screenWidth - 32) * 0.75,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => Container(
                                                width: screenWidth - 32,
                                                height: (screenWidth - 32) * 0.75,
                                                color: Colors.grey[200],
                                                child: const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200))),
                                              ),
                                              errorWidget: (context, url, error) => Container(
                                                width: screenWidth - 32,
                                                height: (screenWidth - 32) * 0.75,
                                                color: Colors.grey[200],
                                                child: const Icon(Icons.error, color: Colors.red),
                                              ),
                                            ),
                                          )
                                        : CarouselSlider(
                                            options: CarouselOptions(
                                              height: (screenWidth - 32) * 0.75,
                                              viewportFraction: 1.0,
                                              enableInfiniteScroll: false,
                                              padEnds: false,
                                              autoPlay: false,
                                              enlargeCenterPage: true,
                                              pageSnapping: true,
                                            ),
                                            items: (_postData!['mediaUrls'] as List).map((url) {
                                              return ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: CachedNetworkImage(
                                                  imageUrl: url,
                                                  width: screenWidth - 32,
                                                  height: (screenWidth - 32) * 0.75,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) => Container(
                                                    width: screenWidth - 32,
                                                    height: (screenWidth - 32) * 0.75,
                                                    color: Colors.grey[200],
                                                    child: const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200))),
                                                  ),
                                                  errorWidget: (context, url, error) => Container(
                                                    width: screenWidth - 32,
                                                    height: (screenWidth - 32) * 0.75,
                                                    color: Colors.grey[200],
                                                    child: const Icon(Icons.error, color: Colors.red),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Semantics(
                                        label: 'Like Post',
                                        child: IconButton(
                                          icon: Icon(
                                            _isLiked ? Icons.favorite : Icons.favorite_border,
                                            color: _isLiked ? const Color(0xFFFF6200) : Colors.grey[600],
                                            size: 28,
                                          ),
                                          onPressed: _toggleLike,
                                        ),
                                      ),
                                      Text(
                                        '$_likeCount Likes',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(color: Colors.grey[700], fontSize: 14),
                                      ),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 26),
                                      const SizedBox(width: 4),
                                      StreamBuilder<QuerySnapshot>(
                                        stream: _firestore.getComments(widget.postId),
                                        builder: (context, snapshot) {
                                          return Text(
                                            '${snapshot.data?.docs.length ?? 0} Comments',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(color: Colors.grey[700], fontSize: 14),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ).animate().fadeIn(duration: 400.ms),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    // Comments Section
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Comments',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestore.getComments(widget.postId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SliverToBoxAdapter(
                              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF6200))));
                        }
                        if (snapshot.hasError) {
                          return SliverToBoxAdapter(
                              child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Error loading comments: ${snapshot.error}',
                                style: Theme.of(context).textTheme.bodyMedium),
                          ));
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return SliverToBoxAdapter(
                              child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('No comments yet',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                          ));
                        }

                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              var comment = snapshot.data!.docs[index];
                              var commentData = comment.data() as Map<String, dynamic>;
                              final commentTimestamp = (commentData['timestamp'] as Timestamp?)?.toDate();
                              final commentTimeAgo =
                                  commentTimestamp != null ? timeago.format(commentTimestamp) : 'Just now';

                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundImage: commentData['profilePicUrl'] != null &&
                                              commentData['profilePicUrl'].isNotEmpty
                                          ? NetworkImage(commentData['profilePicUrl'])
                                          : null,
                                      backgroundColor: Colors.grey[200],
                                      child: commentData['profilePicUrl'] == null || commentData['profilePicUrl'].isEmpty
                                          ? const Icon(Icons.person, color: Colors.grey, size: 16)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                commentData['userName'] ?? 'Anonymous',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                              FutureBuilder<String?>(
                                                future: _firestore.getUserRole(commentData['userId']),
                                                builder: (context, roleSnapshot) {
                                                  if (roleSnapshot.hasData && roleSnapshot.data == 'provider') {
                                                    return const Padding(
                                                      padding: EdgeInsets.only(left: 6),
                                                      child: Icon(Icons.verified, color: Color(0xFFFF6200), size: 14),
                                                    );
                                                  }
                                                  return const SizedBox.shrink();
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            commentData['content'] ?? '',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            commentTimeAgo,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: Colors.grey[600], fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(duration: 400.ms, delay: (100 * index).ms);
                            },
                            childCount: snapshot.data!.docs.length,
                          ),
                        );
                      },
                    ),
                    // Comment Input
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          child: SingleChildScrollView(
                            reverse: true, // Scroll to bottom when keyboard opens
                            child: Row(
                              children: [
                                Expanded(
                                  child: Semantics(
                                    label: 'Comment Input',
                                    child: TextField(
                                      controller: _commentController,
                                      focusNode: _commentFocusNode,
                                      decoration: InputDecoration(
                                        hintText: 'Add a comment...',
                                        filled: true,
                                        fillColor: Colors.grey[100],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(20),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      maxLines: 1,
                                      onSubmitted: (_) => _submitComment(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Semantics(
                                  label: 'Submit Comment',
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.send,
                                      color: _isSubmittingComment ? Colors.grey : const Color(0xFFFF6200),
                                      size: 28,
                                    ),
                                    onPressed: _isSubmittingComment ? null : _submitComment,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)), // Extra padding at bottom
                  ],
                ),
    );
  }*/

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.removeListener(_onFocusChange);
    _commentFocusNode.dispose();
    super.dispose();
  }
}