import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'pages/connections.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final String _baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

  Map<String, dynamic>? _userProfile;
  bool _loading = true;
  String? _error;
  bool _loadingPosts = true;
  List<dynamic> _myPosts = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadMyPosts();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      
      if (token == null || token.isEmpty) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/users/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _userProfile = jsonDecode(response.body);
        });
      } else {
        throw Exception('Failed to load profile');
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load profile';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUploadImage({required bool isProfile}) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return;

      await _uploadImage(file, isProfile: isProfile);
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isProfile ? 'Profile photo updated' : 'Cover photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image update failed: $e')),
      );
    }
  }

  Future<void> _uploadImage(XFile file, {required bool isProfile}) async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    if (token == null || token.isEmpty) throw Exception('Authentication required');

    final uri = Uri.parse('${_baseUrl}${isProfile ? '/api/users/profile-image' : '/api/users/cover-image'}');
    final request = http.MultipartRequest('PUT', uri);
    request.headers['Authorization'] = 'Bearer $token';
    final mimeType = 'image/${file.path.split('.').last.toLowerCase()}';
    request.files.add(await http.MultipartFile.fromPath(
      'image',
      file.path,
      contentType: MediaType.parse(mimeType),
    ));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['message'] ?? 'Upload failed');
    }
  }

  Future<void> _updateProfile(Map<String, dynamic> updatedData) async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      
      if (token == null || token.isEmpty) {
        throw Exception('Authentication required');
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/api/users/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(updatedData),
      );

      if (response.statusCode == 200) {
        setState(() {
          _userProfile = jsonDecode(response.body);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      } else {
        throw Exception('Failed to update profile');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e')),
      );
    }
  }

  Future<void> _loadMyPosts() async {
    setState(() { _loadingPosts = true; });
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) throw Exception('Authentication required');

      final res = await http.get(
        Uri.parse('$_baseUrl/api/posts/mine'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode != 200) throw Exception('Failed');
      setState(() {
        _myPosts = jsonDecode(res.body) as List<dynamic>;
      });
    } catch (_) {
      // keep silent; section will show empty/error state
    } finally {
      if (mounted) setState(() { _loadingPosts = false; });
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) throw Exception('Authentication required');
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/posts/$postId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        setState(() { _myPosts.removeWhere((p) => p['_id'] == postId); });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post deleted')));
      } else {
        throw Exception('Failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _showEditPostDialog(Map<String, dynamic> post) {
    final titleCtrl = TextEditingController(text: post['title'] ?? '');
    final contentCtrl = TextEditingController(text: post['content'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Content', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                const storage = FlutterSecureStorage();
                final token = await storage.read(key: 'auth_token');
                if (token == null || token.isEmpty) throw Exception('Authentication required');
                final res = await http.put(
                  Uri.parse('$_baseUrl/api/posts/${post['_id']}'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'title': titleCtrl.text.trim(),
                    'content': contentCtrl.text.trim(),
                  }),
                );
                if (res.statusCode == 200) {
                  final updated = jsonDecode(res.body) as Map<String, dynamic>;
                  final idx = _myPosts.indexWhere((p) => p['_id'] == post['_id']);
                  if (idx != -1) {
                    setState(() { _myPosts[idx] = updated; });
                  }
                  if (mounted) Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post updated (pending approval)')));
                } else {
                  throw Exception('Failed');
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _userProfile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? 'Profile not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showEditProfileDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.privacy_tip),
            onPressed: () => _showPrivacySettingsDialog(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildProfileHeader(),
              _buildAboutSection(),
              _buildExperienceSection(),
              _buildEducationSection(),
              _buildSkillsSection(),
              _buildConnectionsSection(),
              _buildMyPostsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // Cover Image with edit button
          Stack(
            children: [
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  image: _userProfile!['coverImage'] != null
                      ? DecorationImage(
                          image: NetworkImage(_normalizedUrl(_userProfile!['coverImage'])),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _userProfile!['coverImage'] == null
                    ? const Icon(Icons.image, size: 80, color: Colors.grey)
                    : null,
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: ElevatedButton.icon(
                  onPressed: () => _pickAndUploadImage(isProfile: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Edit cover'),
                ),
              ),
            ],
          ),

          // Profile Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile Image with small edit button
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      backgroundImage: _userProfile!['profileImage'] != null
                          ? NetworkImage(_normalizedUrl(_userProfile!['profileImage']))
                          : null,
                      child: _userProfile!['profileImage'] == null
                          ? const Icon(Icons.person, size: 60, color: Colors.grey)
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: InkWell(
                        onTap: () => _pickAndUploadImage(isProfile: true),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Name and Headline
                Text(
                  _userProfile!['name'] ?? 'No Name',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                if (_userProfile!['headline'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _userProfile!['headline'],
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                if (_userProfile!['location'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on, color: Colors.white70, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _userProfile!['location'],
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ConnectionsPage()),
                        );
                      },
                      icon: const Icon(Icons.group),
                      label: const Text('Connections'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue.shade700,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showEditProfileDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Profile'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _normalizedUrl(String url) {
    if (url.startsWith('http')) return url;
    return _baseUrl + (url.startsWith('/') ? url : '/$url');
  }

  Widget _buildAboutSection() {
    if (_userProfile!['bio'] == null || _userProfile!['bio'].isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'About',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _userProfile!['bio'],
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExperienceSection() {
    final experience = _userProfile!['experience'] as List<dynamic>? ?? [];
    
    if (experience.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Experience',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...experience.map((exp) => _buildExperienceItem(exp)),
          ],
        ),
      ),
    );
  }

  Widget _buildExperienceItem(Map<String, dynamic> exp) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exp['title'] ?? 'No Title',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            exp['company'] ?? 'No Company',
            style: const TextStyle(fontSize: 14, color: Colors.blue),
          ),
          if (exp['location'] != null)
            Text(
              exp['location'],
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          Text(
            _formatDateRange(exp['startDate'], exp['endDate'], exp['current']),
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          if (exp['description'] != null && exp['description'].isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              exp['description'],
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEducationSection() {
    final education = _userProfile!['education'] as List<dynamic>? ?? [];
    
    if (education.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Education',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...education.map((edu) => _buildEducationItem(edu)),
          ],
        ),
      ),
    );
  }

  Widget _buildEducationItem(Map<String, dynamic> edu) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            edu['school'] ?? 'No School',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            '${edu['degree'] ?? 'No Degree'} in ${edu['fieldOfStudy'] ?? 'No Field'}',
            style: const TextStyle(fontSize: 14, color: Colors.blue),
          ),
          Text(
            _formatDateRange(edu['startDate'], edu['endDate'], edu['current']),
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          if (edu['description'] != null && edu['description'].isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              edu['description'],
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkillsSection() {
    final skills = _userProfile!['skills'] as List<dynamic>? ?? [];
    
    if (skills.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skills',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: skills.map((skill) => Chip(
                label: Text(skill),
                backgroundColor: Colors.blue.shade100,
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionsSection() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: ListTile(
        leading: const Icon(Icons.group),
        title: const Text('Connections'),
        subtitle: const Text('Manage your professional connections'),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ConnectionsPage()),
          );
        },
      ),
    );
  }

  Widget _buildMyPostsSection() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('My Posts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadMyPosts,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingPosts)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            else if (_myPosts.isEmpty)
              const Text('You have not posted anything yet.', style: TextStyle(color: Colors.black54))
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myPosts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = _myPosts[i] as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.article),
                    title: Text((p['title'] ?? '').toString()),
                    subtitle: Text('Status: ${p['status'] ?? 'pending'}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditPostDialog(p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deletePost(p['_id'].toString()),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(String? startDate, String? endDate, bool? current) {
    String start = startDate != null ? DateTime.parse(startDate).year.toString() : '';
    String end = current == true 
        ? 'Present' 
        : endDate != null ? DateTime.parse(endDate).year.toString() : '';
    
    if (start.isNotEmpty && end.isNotEmpty) {
      return '$start - $end';
    } else if (start.isNotEmpty) {
      return start;
    } else {
      return '';
    }
  }

  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => _EditProfileDialog(
        userProfile: _userProfile!,
        onSave: _updateProfile,
      ),
    );
  }

  void _showPrivacySettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => _PrivacySettingsDialog(
        privacySettings: _userProfile!['privacySettings'] ?? {},
        onSave: (settings) async {
          try {
            const storage = FlutterSecureStorage();
            final token = await storage.read(key: 'auth_token');
            
            if (token == null || token.isEmpty) {
              throw Exception('Authentication required');
            }

            final response = await http.put(
              Uri.parse('$_baseUrl/api/users/privacy-settings'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(settings),
            );

            if (response.statusCode == 200) {
              setState(() {
                _userProfile!['privacySettings'] = settings;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Privacy settings updated')),
              );
            } else {
              throw Exception('Failed to update privacy settings');
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update settings: $e')),
            );
          }
        },
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  final Function(Map<String, dynamic>) onSave;

  const _EditProfileDialog({
    required this.userProfile,
    required this.onSave,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, dynamic> _formData;
  late TextEditingController _currentTitleCtrl;
  late TextEditingController _currentCompanyCtrl;
  late TextEditingController _currentLocationCtrl;

  @override
  void initState() {
    super.initState();
    _formData = Map.from(widget.userProfile);
    final experience = (widget.userProfile['experience'] as List<dynamic>?) ?? [];
    final currentExp = experience.cast<Map<String, dynamic>?>().firstWhere(
      (e) => (e?['current'] == true),
      orElse: () => null,
    );
    _currentTitleCtrl = TextEditingController(text: currentExp?['title'] ?? '');
    _currentCompanyCtrl = TextEditingController(text: currentExp?['company'] ?? '');
    _currentLocationCtrl = TextEditingController(text: currentExp?['location'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Edit Profile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        initialValue: _formData['headline'] ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Professional Headline',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _formData['headline'] = value,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _formData['bio'] ?? '',
                        decoration: const InputDecoration(
                          labelText: 'About (Bio)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (value) => _formData['bio'] = value,
                      ),
                      const SizedBox(height: 16),
                      // Current Position
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Current Position',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _currentTitleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Title (e.g., Software Engineer)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _currentCompanyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Company/Organization',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _currentLocationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _formData['location'] ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Location',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _formData['location'] = value,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _formData['website'] ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Website',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _formData['website'] = value,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _formData['linkedin'] ?? '',
                        decoration: const InputDecoration(
                          labelText: 'LinkedIn',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _formData['linkedin'] = value,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _formData['twitter'] ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Twitter',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _formData['twitter'] = value,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _formData['github'] ?? '',
                        decoration: const InputDecoration(
                          labelText: 'GitHub',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _formData['github'] = value,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Merge current position into experience array
                    final title = _currentTitleCtrl.text.trim();
                    final company = _currentCompanyCtrl.text.trim();
                    final loc = _currentLocationCtrl.text.trim();
                    List<dynamic> experience = List<dynamic>.from(_formData['experience'] ?? []);
                    final currentIndex = experience.indexWhere((e) => (e is Map && e['current'] == true));
                    final payload = {
                      'title': title,
                      'company': company,
                      'location': loc,
                      'current': true,
                    };
                    if (title.isNotEmpty || company.isNotEmpty || loc.isNotEmpty) {
                      if (currentIndex >= 0) {
                        // Replace current
                        experience[currentIndex] = {
                          ...Map<String, dynamic>.from(experience[currentIndex] as Map),
                          ...payload,
                        };
                      } else {
                        experience.insert(0, payload);
                      }
                    } else if (currentIndex >= 0) {
                      // Remove if fields all empty
                      experience.removeAt(currentIndex);
                    }
                    _formData['experience'] = experience;
                    widget.onSave(_formData);
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySettingsDialog extends StatefulWidget {
  final Map<String, dynamic> privacySettings;
  final Function(Map<String, dynamic>) onSave;

  const _PrivacySettingsDialog({
    required this.privacySettings,
    required this.onSave,
  });

  @override
  State<_PrivacySettingsDialog> createState() => _PrivacySettingsDialogState();
}

class _PrivacySettingsDialogState extends State<_PrivacySettingsDialog> {
  late Map<String, dynamic> _settings;

  @override
  void initState() {
    super.initState();
    _settings = Map.from(widget.privacySettings);
    
    // Set defaults if not present
    _settings['profileVisibility'] ??= 'public';
    _settings['showEmail'] ??= false;
    _settings['showPhone'] ??= false;
    _settings['showExperience'] ??= true;
    _settings['showEducation'] ??= true;
    _settings['showSkills'] ??= true;
    _settings['showConnections'] ??= true;
    _settings['allowMessages'] ??= true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Privacy Settings',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile Visibility',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _settings['profileVisibility'],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'public', child: Text('Public')),
                        DropdownMenuItem(value: 'private', child: Text('Private')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _settings['profileVisibility'] = value;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'What others can see',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Show Email'),
                      subtitle: const Text('Allow others to see your email'),
                      value: _settings['showEmail'],
                      onChanged: (value) {
                        setState(() {
                          _settings['showEmail'] = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Phone'),
                      subtitle: const Text('Allow others to see your phone number'),
                      value: _settings['showPhone'],
                      onChanged: (value) {
                        setState(() {
                          _settings['showPhone'] = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Experience'),
                      subtitle: const Text('Allow others to see your work experience'),
                      value: _settings['showExperience'],
                      onChanged: (value) {
                        setState(() {
                          _settings['showExperience'] = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Education'),
                      subtitle: const Text('Allow others to see your education'),
                      value: _settings['showEducation'],
                      onChanged: (value) {
                        setState(() {
                          _settings['showEducation'] = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Skills'),
                      subtitle: const Text('Allow others to see your skills'),
                      value: _settings['showSkills'],
                      onChanged: (value) {
                        setState(() {
                          _settings['showSkills'] = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Connections'),
                      subtitle: const Text('Allow others to see your connections'),
                      value: _settings['showConnections'],
                      onChanged: (value) {
                        setState(() {
                          _settings['showConnections'] = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Allow Messages'),
                      subtitle: const Text('Allow others to send you messages'),
                      value: _settings['allowMessages'],
                      onChanged: (value) {
                        setState(() {
                          _settings['allowMessages'] = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(_settings);
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
