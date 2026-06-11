import Foundation

struct MediaRemotePayload: Sendable {
    let title: String
    let artist: String
    let album: String
    let artworkData: Data?
    let isPlaying: Bool
}

enum MediaRemoteCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

@MainActor
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private typealias GetInfoFunction =
        @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFunction =
        @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias SendCommandFunction =
        @convention(c) (Int, CFDictionary?) -> Bool

    private let handle: UnsafeMutableRawPointer?
    private let getInfo: GetInfoFunction?
    private let getIsPlaying: GetIsPlayingFunction?
    private let sendCommandFunction: SendCommandFunction?

    private init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(path, RTLD_NOW)

        if let handle {
            getInfo = Self.load(handle: handle, symbol: "MRMediaRemoteGetNowPlayingInfo")
            getIsPlaying = Self.load(handle: handle, symbol: "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            sendCommandFunction = Self.load(handle: handle, symbol: "MRMediaRemoteSendCommand")
        } else {
            getInfo = nil
            getIsPlaying = nil
            sendCommandFunction = nil
        }
    }

    var isAvailable: Bool {
        getInfo != nil && getIsPlaying != nil && sendCommandFunction != nil
    }

    func fetchNowPlaying() async -> MediaRemotePayload? {
        guard let getInfo, let getIsPlaying else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            getInfo(.main) { info in
                let dictionary = info as NSDictionary?

                let title = dictionary?["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = dictionary?["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                let album = dictionary?["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                let artworkData = dictionary?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

                guard !title.isEmpty || !artist.isEmpty || !album.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                getIsPlaying(.main) { isPlaying in
                    continuation.resume(
                        returning: MediaRemotePayload(
                            title: title,
                            artist: artist,
                            album: album,
                            artworkData: artworkData,
                            isPlaying: isPlaying
                        )
                    )
                }
            }
        }
    }

    @discardableResult
    func send(_ command: MediaRemoteCommand) -> Bool {
        guard let sendCommandFunction else {
            return false
        }

        return sendCommandFunction(command.rawValue, nil)
    }
    private static func load<T>(handle: UnsafeMutableRawPointer, symbol: String) -> T? {
        guard let rawSymbol = dlsym(handle, symbol) else {
            return nil
        }

        return unsafeBitCast(rawSymbol, to: T.self)
    }
}
