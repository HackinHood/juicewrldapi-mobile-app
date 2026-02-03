import Flutter
import UIKit
import AVFoundation
import Intents

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nativeMetadataChannelRegistered = false
  private func _hasSiriEntitlement() -> Bool {
    guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else { return false }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return false }
    guard let raw = String(data: data, encoding: .isoLatin1) else { return false }
    guard let start = raw.range(of: "<plist")?.lowerBound else { return false }
    guard let end = raw.range(of: "</plist>")?.upperBound else { return false }
    let plistString = String(raw[start..<end])
    guard let plistData = plistString.data(using: .utf8) else { return false }
    guard let obj = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) else { return false }
    guard let dict = obj as? [String: Any] else { return false }
    guard let entitlements = dict["Entitlements"] as? [String: Any] else { return false }
    if let v = entitlements["com.apple.developer.siri"] as? Bool { return v }
    return entitlements["com.apple.developer.siri"] != nil
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    _registerNativeMetadataChannelIfNeeded()
    _registerSiriPlaybackChannel()
    if _hasSiriEntitlement() {
      INPreferences.requestSiriAuthorization { _ in }
    }

    return didFinish
  }
  
  override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    if userActivity.activityType == "com.juicewrldapi.musicapp.play" {
      if let mediaItemId = userActivity.userInfo?["mediaItemId"] as? String {
        _handleSiriPlayback(mediaItemId: mediaItemId)
      }
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
  
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if url.scheme == "musiclibraryapp" && url.host == "play" {
      if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
         let itemId = components.queryItems?.first(where: { $0.name == "itemId" })?.value {
        _handleSiriPlayback(mediaItemId: itemId)
        return true
      }
    }
    return super.application(app, open: url, options: options)
  }
  
  private func _registerSiriPlaybackChannel() {
    guard let registrar = self.registrar(forPlugin: "SiriPlaybackPlugin") else {
      return
    }
    let channel = FlutterMethodChannel(name: "siri_playback", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "play" {
        guard let args = call.arguments as? [String: Any],
              let itemId = args["itemId"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "itemId is required", details: nil))
          return
        }
        self._handleSiriPlayback(mediaItemId: itemId)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
  
  private func _handleSiriPlayback(mediaItemId: String) {
    guard let controller = self.window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(name: "siri_playback", binaryMessenger: controller.binaryMessenger)
    channel.invokeMethod("play", arguments: ["itemId": mediaItemId])
  }

  private func _registerNativeMetadataChannelIfNeeded() {
    if nativeMetadataChannelRegistered { return }
    guard let registrar = self.registrar(forPlugin: "NativeMetadataPlugin") else {
      return
    }
    let channel = FlutterMethodChannel(name: "native_metadata", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method != "read" {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String,
            !filePath.isEmpty else {
        result([String: Any]())
        return
      }

      let url: URL
      if filePath.hasPrefix("file://"), let u = URL(string: filePath) {
        url = u
      } else {
        url = URL(fileURLWithPath: filePath)
      }

      let asset = AVURLAsset(url: url)
      let keys = ["duration", "commonMetadata", "metadata"]
      asset.loadValuesAsynchronously(forKeys: keys) {
        var title: String?
        var artist: String?
        var album: String?
        var genre: String?
        var year: Int?
        var durationMs: Int?
        var artworkData: Data?

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        if durationSeconds.isFinite && durationSeconds > 0 {
          durationMs = Int((durationSeconds * 1000.0).rounded())
        }

        for item in asset.commonMetadata {
          guard let key = item.commonKey?.rawValue else { continue }
          if key == AVMetadataKey.commonKeyTitle.rawValue {
            title = (item.stringValue ?? title)
          } else if key == AVMetadataKey.commonKeyArtist.rawValue {
            artist = (item.stringValue ?? artist)
          } else if key == AVMetadataKey.commonKeyAlbumName.rawValue {
            album = (item.stringValue ?? album)
          } else if key == AVMetadataKey.commonKeyArtwork.rawValue {
            if let data = item.dataValue {
              artworkData = data
            } else if let dict = item.value as? NSDictionary {
              if let data = dict["data"] as? Data {
                artworkData = data
              }
            }
          }
        }

        let id3Items = asset.metadata(forFormat: .id3Metadata)
        for item in id3Items {
          guard let key = item.key as? String else { continue }
          if (title == nil || title?.isEmpty == true) && key == AVMetadataKey.id3MetadataKeyTitleDescription.rawValue {
            title = item.stringValue ?? title
          }
          if (artist == nil || artist?.isEmpty == true) && key == AVMetadataKey.id3MetadataKeyLeadPerformer.rawValue {
            artist = item.stringValue ?? artist
          }
          if (album == nil || album?.isEmpty == true) && key == AVMetadataKey.id3MetadataKeyAlbumTitle.rawValue {
            album = item.stringValue ?? album
          }
          if (genre == nil || genre?.isEmpty == true) && key == AVMetadataKey.id3MetadataKeyContentType.rawValue {
            genre = item.stringValue ?? genre
          }
          if (artworkData == nil || artworkData?.isEmpty == true) && key == AVMetadataKey.id3MetadataKeyAttachedPicture.rawValue {
            if let data = item.dataValue {
              artworkData = data
            }
          }
        }

        if year == nil {
          for item in asset.metadata {
            if let keySpace = item.keySpace, keySpace == .iTunes {
              if let key = item.key as? String {
                if key == AVMetadataKey.iTunesMetadataKeyReleaseDate.rawValue {
                  if let dateString = item.stringValue, dateString.count >= 4 {
                    let y = String(dateString.prefix(4))
                    year = Int(y)
                  }
                }
                if key == AVMetadataKey.iTunesMetadataKeyUserGenre.rawValue {
                  genre = (item.stringValue ?? genre)
                }
              }
            }
          }
        }

        var payload: [String: Any] = [:]
        if let title, !title.isEmpty { payload["title"] = title }
        if let artist, !artist.isEmpty { payload["artist"] = artist }
        if let album, !album.isEmpty { payload["album"] = album }
        if let genre, !genre.isEmpty { payload["genre"] = genre }
        if let year { payload["year"] = year }
        if let durationMs { payload["durationMs"] = durationMs }
        if let artworkData, !artworkData.isEmpty {
          payload["artworkBytes"] = FlutterStandardTypedData(bytes: artworkData)
        }

        DispatchQueue.main.async {
          result(payload)
        }
      }
    }

    nativeMetadataChannelRegistered = true
  }
}
