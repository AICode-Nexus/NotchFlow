import AppKit
import Foundation

struct MusicAppPayload: Sendable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
}

enum MusicAppleScriptBridge {
    static func fetchNowPlaying() -> MusicAppPayload? {
        let script = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    set stateText to (player state as text)
                    return trackName & "|||" & artistName & "|||" & albumName & "|||" & stateText
                end if
            end tell
        end if
        return ""
        """

        guard let output = run(script: script), !output.isEmpty else {
            return nil
        }

        let parts = output.components(separatedBy: "|||")
        guard parts.count == 4 else {
            return nil
        }

        return MusicAppPayload(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: parts[3].lowercased().contains("playing")
        )
    }

    @discardableResult
    static func togglePlayPause() -> Bool {
        run(script: #"tell application "Music" to playpause"#) != nil
    }

    @discardableResult
    static func nextTrack() -> Bool {
        run(script: #"tell application "Music" to next track"#) != nil
    }

    @discardableResult
    static func previousTrack() -> Bool {
        run(script: #"tell application "Music" to previous track"#) != nil
    }

    private static func run(script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if error != nil {
            return nil
        }

        return result.stringValue
    }
}
