import Orion
import SwiftUI

//

struct BaseLyricsGroup: HookGroup { }

struct LegacyLyricsGroup: HookGroup { }
struct ModernLyricsGroup: HookGroup { }
struct V91LyricsGroup: HookGroup { }  // For Spotify 9.1.x - excludes incompatible hooks
struct LyricsErrorHandlingGroup: HookGroup { }  // ErrorViewController hooks - not compatible with 9.1.x

var lyricsState = LyricsLoadingState()

var hasShownRestrictedPopUp = false
var hasShownUnauthorizedPopUp = false

private let geniusLyricsRepository = GeniusLyricsRepository()
private let petitLyricsRepository = PetitLyricsRepository()

// Overload for 9.1.6 where we only have track ID from URL
private func loadCustomLyricsForTrackId(_ trackId: String) throws -> Lyrics {
    LogHelper.log("🔍 loadCustomLyricsForTrackId called for: \(trackId)")
    
    let source = UserDefaults.lyricsSource
    
    // Check if we have captured metadata from the UI hooks
    let hasMetadata = capturedTrackId == trackId && capturedTrackTitle != nil && capturedArtistName != nil
    
    if hasMetadata {
        LogHelper.log("✅ Found captured metadata for track \(trackId)")
        LogHelper.log("   Title: \(capturedTrackTitle ?? "nil")")
        LogHelper.log("   Artist: \(capturedArtistName ?? "nil")")
    }
    
    // For 9.1.6: Genius/LRCLIB/Petit need track title/artist
    // They will only work if we have captured metadata
    let needsMetadata = source == .genius || source == .lrclib || source == .petit
    
    if needsMetadata && !hasMetadata {
        LogHelper.logError("⚠️ \(source) requires track metadata not captured yet for Spotify 9.1.6")
        LogHelper.logError("💡 Use Musixmatch instead for guaranteed 9.1.6 compatibility")
        throw LyricsError.noSuchSong
    }
    
    // Create search query with available data
    let searchQuery = LyricsSearchQuery(
        title: capturedTrackTitle ?? "",
        primaryArtist: capturedArtistName ?? "",
        spotifyTrackId: trackId
    )
    
    let options = UserDefaults.lyricsOptions
    
    var repository: LyricsRepository

    switch source {
    case .genius:
        repository = geniusLyricsRepository
    case .lrclib:
        repository = LrclibLyricsRepository.shared
    case .musixmatch:
        repository = MusixmatchLyricsRepository.shared
    case .petit:
        repository = petitLyricsRepository
    case .notReplaced:
        throw LyricsError.invalidSource
    }
    
    let lyricsDto: LyricsDto
    
    lyricsState = LyricsLoadingState()
    
    do {
        LogHelper.log("📥 Fetching lyrics from \(source) for track ID: \(trackId)")
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
        LogHelper.log("✅ Successfully fetched lyrics from \(source)")
    }
    catch let error {
        LogHelper.logError("❌ Failed to fetch lyrics: \(error)")
        throw error
    }
    
    lyricsState.isEmpty = lyricsDto.lines.isEmpty
    
    lyricsState.wasRomanized = lyricsDto.romanization == .romanized
        || (lyricsDto.romanization == .canBeRomanized && UserDefaults.lyricsOptions.romanization)
    
    lyricsState.loadedSuccessfully = true

    LogHelper.log("📊 Lyrics stats: \(lyricsDto.lines.count) lines, isEmpty: \(lyricsDto.lines.isEmpty), timeSynced: \(lyricsDto.timeSynced)")

    let lyrics = Lyrics.with {
        $0.data = lyricsDto.toSpotifyLyricsData(source: source.description)
    }
    
    LogHelper.log("✅ Successfully created Lyrics object")
    return lyrics
}

//

private func loadCustomLyricsForCurrentTrack() throws -> Lyrics {
    NSLog("[EeveeSpotify] loadCustomLyricsForCurrentTrack called")
    
    guard
        let track = statefulPlayer?.currentTrack() ??
                    nowPlayingScrollViewController?.loadedTrack
        else {
            NSLog("[EeveeSpotify] No current track found!")
            throw LyricsError.noCurrentTrack
        }
    
    let trackTitle = track.trackTitle()
    let artistName = EeveeSpotify.hookTarget == .lastAvailableiOS14
        ? track.artistTitle()
        : track.artistName()
    
    NSLog("[EeveeSpotify] Loading lyrics for: \(trackTitle) - \(artistName)")
    
    let searchQuery = LyricsSearchQuery(
        title: trackTitle,
        primaryArtist: artistName,
        spotifyTrackId: track.trackIdentifier
    )
    
    let options = UserDefaults.lyricsOptions
    var source = UserDefaults.lyricsSource
    
    // switched to swift 5.8 syntax to compile with Theos on Linux.
    var repository: LyricsRepository

    switch source {
    case .genius:
        repository = geniusLyricsRepository
    case .lrclib:
        repository = LrclibLyricsRepository.shared
    case .musixmatch:
        repository = MusixmatchLyricsRepository.shared
    case .petit:
        repository = petitLyricsRepository
    case .notReplaced:
        throw LyricsError.invalidSource
    }
    
    let lyricsDto: LyricsDto
    
    lyricsState = LyricsLoadingState()
    
    do {
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
    }
    catch let error {
        if let error = error as? LyricsError {
            lyricsState.fallbackError = error
            
            switch error {
                
            case .invalidMusixmatchToken:
                if !hasShownUnauthorizedPopUp {
                    PopUpHelper.showPopUp(
                        delayed: false,
                        message: "musixmatch_unauthorized_popup".localized,
                        buttonText: "OK".uiKitLocalized
                    )
                    
                    hasShownUnauthorizedPopUp.toggle()
                }
            
            case .musixmatchRestricted:
                if !hasShownRestrictedPopUp {
                    PopUpHelper.showPopUp(
                        delayed: false,
                        message: "musixmatch_restricted_popup".localized,
                        buttonText: "OK".uiKitLocalized
                    )
                    
                    hasShownRestrictedPopUp.toggle()
                }
                
            default:
                break
            }
        }
        else {
            lyricsState.fallbackError = .unknownError
        }
        
        if source == .genius || !UserDefaults.lyricsOptions.geniusFallback {
            throw error
        }
        
        source = .genius
        repository = GeniusLyricsRepository()
        
        lyricsDto = try repository.getLyrics(searchQuery, options: options)
    }
    
    lyricsState.isEmpty = lyricsDto.lines.isEmpty
    
    lyricsState.wasRomanized = lyricsDto.romanization == .romanized
        || (lyricsDto.romanization == .canBeRomanized && UserDefaults.lyricsOptions.romanization)
    
    lyricsState.loadedSuccessfully = true

    let lyrics = Lyrics.with {
        $0.data = lyricsDto.toSpotifyLyricsData(source: source.description)
    }
    
    return lyrics
}

func getLyricsDataForCurrentTrack(_ originalPath: String, originalLyrics: Lyrics? = nil) throws -> Data {
    LogHelper.log("🔍 getLyricsDataForCurrentTrack called for path: \(originalPath)")
    
    // Extract track ID from URL path since player objects are nil in 9.1.6
    // Format: /color-lyrics/v2/track/{trackId} or /lyrics/.../{trackId}
    let trackIdentifier: String
    if let range = originalPath.range(of: #"/track/([a-zA-Z0-9]+)"#, options: .regularExpression) {
        let match = originalPath[range]
        trackIdentifier = String(match.split(separator: "/").last ?? "")
        LogHelper.log("✅ Extracted track ID from URL: \(trackIdentifier)")
    } else {
        LogHelper.logError("❌ Could not extract track ID from path: \(originalPath)")
        throw LyricsError.noCurrentTrack
    }
    
    // Verify track ID was extracted
    if trackIdentifier.isEmpty {
        LogHelper.logError("❌ Extracted track ID is empty!")
        throw LyricsError.noCurrentTrack
    }
    
    // Try to capture metadata from view hierarchy at lyrics request time
    // Always try to capture fresh metadata when track changes
    // Clear old metadata if track ID changed
    if capturedTrackId != trackIdentifier {
        LogHelper.log("🔄 Track changed from \(capturedTrackId ?? "none") to \(trackIdentifier)")
        capturedTrackTitle = nil
        capturedArtistName = nil
        capturedTrackId = nil
        
        // Delay to let Now Playing UI fully update before capturing
        Thread.sleep(forTimeInterval: 0.3)
    }
    
    LogHelper.log("🔍 Attempting to capture metadata for track \(trackIdentifier)...")
    
    // 1. Try MPNowPlayingInfoCenter first (System info)
    var info: (title: String?, artist: String?)? = getSystemNowPlayingInfo()
    
    // 2. Fallback to view hierarchy scraping if system info failed
    if info == nil {
        LogHelper.log("⚠️ MPNowPlayingInfoCenter failed, falling back to view hierarchy scraping...")
        info = searchViewHierarchyForTrackInfo()
    }

    if let info = info {
        capturedTrackTitle = info.title
        capturedArtistName = info.artist
        capturedTrackId = trackIdentifier
        LogHelper.log("✅ Captured metadata: '\(info.title ?? "")' by '\(info.artist ?? "")'")
    } else {
        LogHelper.log("⚠️ Failed to capture metadata from any source")
        // Keep old metadata if we fail to capture new - better than nothing
    }
    
    // Use track ID version for 9.1.6 where we don't have track objects
    var lyrics = try loadCustomLyricsForTrackId(trackIdentifier)
    
    let lyricsColorsSettings = UserDefaults.lyricsColors
    
    if lyricsColorsSettings.displayOriginalColors, let originalLyrics = originalLyrics {
        lyrics.colors = originalLyrics.colors
    }
    else {
        // For 9.1.6, we don't have track object to extract color from
        // Use static color if enabled, otherwise use background color or gray
        var color: Color
        
        if lyricsColorsSettings.useStaticColor {
            color = Color(hex: lyricsColorsSettings.staticColor)
        }
        else if let uiColor = backgroundViewModel?.color() {
            color = Color(uiColor)
                .normalized(lyricsColorsSettings.normalizationFactor)
        }
        else {
            color = Color.gray
        }
        
        lyrics.colors = LyricsColors.with {
            $0.backgroundColor = color.uInt32
            $0.lineColor = Color.black.uInt32
            $0.activeLineColor = Color.white.uInt32
        }
    }
    
    let serializedData = try lyrics.serializedData()
    LogHelper.log("📤 Returning lyrics data: \(serializedData.count) bytes")
    return serializedData
}
