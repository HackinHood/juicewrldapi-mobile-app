import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:music_library_app/screens/server_folder_tree_screen.dart';
import 'package:music_library_app/services/master_server_service.dart';
import 'package:music_library_app/services/auto_sync_service.dart';
import 'package:music_library_app/services/sync_service.dart';
import 'package:music_library_app/services/server_download_sync_service.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/services/download_service.dart';
import 'package:music_library_app/services/server_root_prefs.dart';
import 'package:music_library_app/utils/permissions.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncing = false;
  bool _autoSyncEnabled = false;
  int _totalTracks = 0;
  int _downloadedTracks = 0;
  int _playlists = 0;
  DateTime? _lastSync;
  String _version = '';
  ServerDownloadSyncState _serverSyncState = ServerDownloadSyncService.state;
  StreamSubscription? _serverSyncSub;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _loadAutoSync();
    _loadVersion();
    _loadOverview();
    _serverSyncSub = ServerDownloadSyncService.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _serverSyncState = s;
        _syncing = s.running;
      });
    });
  }

  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await SyncService.isLoggedIn();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = isLoggedIn;
    });
  }

  @override
  void dispose() {
    _serverSyncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAutoSync() async {
    final enabled = await AutoSyncService.isEnabled();
    if (!mounted) return;
    setState(() {
      _autoSyncEnabled = enabled;
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _version = '1.0.0+1';
      });
    }
  }

  Future<void> _loadOverview() async {
    final mediaItems = await StorageService.getAllMediaItems();
    final playlists = await StorageService.getAllPlaylists();
    final lastSync = await ServerDownloadSyncService.getLastRunTime();
    final downloaded = mediaItems.where((m) => m.isDownloaded).length;

    if (!mounted) return;
    setState(() {
      _totalTracks = mediaItems.length;
      _downloadedTracks = downloaded;
      _playlists = playlists.length;
      _lastSync = lastSync;
    });
  }

  Future<void> _runFullSync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
    });
    try {
      ServerDownloadSyncService.start();
      await _loadOverview();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync started')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  String _formatTimestamp(DateTime time) {
    final date = '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final clock = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return '$date $clock';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildStatusCard(),
          const SizedBox(height: 8),
          _buildLibraryCard(),
          const SizedBox(height: 8),
          _buildSyncCard(),
          const Divider(),
          _buildSectionHeader('Account'),
          _buildLoginSection(),
          const Divider(),
          _buildSectionHeader('Sync'),
          _buildSyncSection(),
          const Divider(),
          _buildSectionHeader('Permissions'),
          _buildPermissionsSection(),
          const Divider(),
          _buildSectionHeader('Storage'),
          _buildStorageSection(),
          const Divider(),
          _buildSectionHeader('About'),
          _buildAboutSection(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_download, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Server sync',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _lastSync == null
                  ? 'Last sync: never'
                  : 'Last sync: ${_formatTimestamp(_lastSync!)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _serverSyncState.running
                  ? 'Syncing: ${_serverSyncState.completed}/${_serverSyncState.total} completed'
                  : 'Sync downloads missing files from selected server folders',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Library',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric('Tracks', _totalTracks.toString()),
                _buildMetric('Downloaded', _downloadedTracks.toString()),
                _buildMetric('Playlists', _playlists.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sync',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Download missing files from selected server folders.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: !_syncing ? _runFullSync : null,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.sync),
                label: Text(_syncing ? 'Syncing...' : 'Sync Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLoginSection() {
    return ListTile(
      leading: const Icon(Icons.account_circle),
      title: Text(_isLoggedIn ? 'Paired' : 'Not paired'),
      subtitle: Text(_isLoggedIn ? 'Tap to disconnect' : 'Tap to enter pairing code'),
      trailing: _isLoggedIn ? const Icon(Icons.logout) : const Icon(Icons.link),
      onTap: _isLoggedIn ? _logout : _showPairingDialog,
    );
  }

  Widget _buildSyncSection() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync Now'),
          subtitle: const Text('Download missing files from selected server folders'),
          trailing: _syncing ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ) : const Icon(Icons.sync),
          onTap: _syncing ? null : _syncNow,
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('Server folders'),
          subtitle: FutureBuilder<Set<String>?>(
            future: ServerRootPrefs.getIncludedPrefixes(),
            builder: (context, snapshot) {
              final inc = snapshot.data;
              if (inc == null) return const Text('All folders');
              return Text('${inc.length} included');
            },
          ),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const ServerFolderTreeScreen()),
            );
            if (changed == true) {
              if (!mounted) return;
              setState(() {});
            }
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.sync_alt),
          title: const Text('Auto Sync'),
          subtitle: const Text('Automatically download missing files'),
          value: _autoSyncEnabled,
          onChanged: (value) async {
            setState(() {
              _autoSyncEnabled = value;
            });
            await AutoSyncService.setEnabled(value);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(value ? 'Auto sync enabled' : 'Auto sync disabled')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPermissionsSection() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.storage),
          title: const Text('Storage Permission'),
          subtitle: const Text('Required for downloading music'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _requestStoragePermission,
        ),
        ListTile(
          leading: const Icon(Icons.volume_up),
          title: const Text('Audio Permission'),
          subtitle: const Text('Required for playing music'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _requestAudioPermission,
        ),
        ListTile(
          leading: const Icon(Icons.notifications),
          title: const Text('Notification Permission'),
          subtitle: const Text('Required for background playback'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _requestNotificationPermission,
        ),
      ],
    );
  }

  Widget _buildStorageSection() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.folder),
          title: const Text('Download Location'),
          subtitle: FutureBuilder<String>(
            future: DownloadService.getDownloadDirectory(),
            builder: (context, snapshot) {
              final v = snapshot.data;
              return Text(v ?? '');
            },
          ),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _changeDownloadLocation,
        ),
        ListTile(
          leading: const Icon(Icons.delete),
          title: const Text('Clear Cache'),
          subtitle: const Text('Free up storage space'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _clearCache,
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text('Delete whole library'),
          subtitle: const Text('Removes all local library data and downloads'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _deleteWholeLibrary,
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info),
          title: const Text('Version'),
          subtitle: Text(_version),
        ),
        ListTile(
          leading: const Icon(Icons.help),
          title: const Text('Help & Support'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _showHelp,
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip),
          title: const Text('Privacy Policy'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: _showPrivacyPolicy,
        ),
      ],
    );
  }

  void _syncNow() async {
    await _runFullSync();
  }

  void _showPairingDialog() {
    final codeController = TextEditingController();
    final deviceName = 'Mobile-${Platform.operatingSystem}';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pair device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                LengthLimitingTextInputFormatter(8),
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Pairing code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final success = await SyncService.pairWithCode(
                codeController.text,
                deviceName: deviceName,
              );
              if (success) {
                if (!context.mounted) return;
                setState(() {
                  _isLoggedIn = true;
                });
                Navigator.pop(context);
              } else {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pairing failed')),
                );
              }
            },
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    await SyncService.logout();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
    });
  }

  void _requestStoragePermission() async {
    final granted = await Permissions.requestStoragePermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(granted ? 'Storage permission granted' : 'Storage permission denied')),
    );
  }

  void _requestAudioPermission() async {
    final granted = await Permissions.requestAudioPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(granted ? 'Audio permission granted' : 'Audio permission denied')),
    );
  }

  void _requestNotificationPermission() async {
    final granted = await Permissions.requestNotificationPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(granted ? 'Notification permission granted' : 'Notification permission denied')),
    );
  }

  Future<void> _changeDownloadLocation() async {
    final options = <String, String>{};
    final appDocs = await getApplicationDocumentsDirectory();
    options['App storage'] = '${appDocs.path}/Music';
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        options['External storage'] = '${ext.path}/Music';
      }
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        options['Downloads'] = '${downloads.path}/Music';
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in options.entries)
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(e.key),
                  subtitle: Text(e.value),
                  onTap: () async {
                    await DownloadService.setDownloadDirectory(e.value);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    setState(() {});
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cache'),
        content: const Text('This clears cached server items and in-memory image cache.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await StorageService.deleteAllCachedServerItems();
    await MasterServerService.clearCacheMetadata();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cache cleared')),
    );
    await _loadOverview();
  }

  Future<void> _deleteWholeLibrary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete whole library'),
        content: const Text('This will delete your local database and downloaded files.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final downloadDir = await DownloadService.getDownloadDirectory();
    final musicDir = Directory(downloadDir);
    if (await musicDir.exists()) {
      await musicDir.delete(recursive: true);
    }
    final docs = await getApplicationDocumentsDirectory();
    final artDir = Directory('${docs.path}/AlbumArt');
    if (await artDir.exists()) {
      await artDir.delete(recursive: true);
    }

    await StorageService.deleteAllLibraryData();
    await MasterServerService.clearCacheMetadata();
    await ServerRootPrefs.setFolderRules(includedPrefixes: null, excludedPrefixes: {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Library deleted')),
    );
    await _loadOverview();
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const Text('Use Sync Now to refresh your library. If downloads fail, check Storage permission and your download location.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const Text('This app stores your library database and preferences locally. If you log in, it syncs your library and playlists with the server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
