import Orion
import UIKit
import MediaPlayer

// Global variables to store captured track metadata for 9.1.6
var capturedTrackTitle: String?
var capturedArtistName: String?
var capturedTrackId: String?

// Function to get metadata from MPNowPlayingInfoCenter
func getSystemNowPlayingInfo() -> (title: String, artist: String)? {
    guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
        NSLog("[EeveeSpotify] ⚠️ No MPNowPlayingInfo available")
        return nil
    }
    
    guard let title = info[MPMediaItemPropertyTitle] as? String,
          let artist = info[MPMediaItemPropertyArtist] as? String else {
        NSLog("[EeveeSpotify] ⚠️ MPNowPlayingInfo missing title or artist")
        return nil
    }
    
    NSLog("[EeveeSpotify] ✅ Captured from System: '\(title)' by '\(artist)'")
    return (title, artist)
}

// Function to search the view hierarchy for track info
func searchViewHierarchyForTrackInfo() -> (title: String?, artist: String?)? {
    guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
        NSLog("[EeveeSpotify] 🔍 No key window found")
        return nil
    }
    
    NSLog("[EeveeSpotify] 🔍 Searching view hierarchy for track info...")
    
    // Common UI labels to exclude (including artist page labels)
    let excludedLabels = ["Home", "Search", "Library", "Premium", "Your Library", 
                          "Search", "Home", "Following", "Notifications", "Settings",
                          "Play", "Pause", "Next", "Previous", "Shuffle", "Repeat",
                          "Create", "Add", "More", "Share", "Like", "Liked",
                          "Explore", "About", "Related Artists", "Merch", "Go to store",
                          "Download", "Queue", "Connect", "Devices", "Lyrics", "Lyrics preview",
                          "Release countdown", "Upcoming"]
    
    // Search for labels that might contain track info
    var allLabels: [(text: String, fontSize: CGFloat, y: CGFloat, className: String)] = []
    
    func searchView(_ view: UIView, depth: Int = 0) {
        let className = String(describing: type(of: view))
        
        // Look for UILabel with substantial text
        if let label = view as? UILabel, let text = label.text, 
           text.count > 2 && !excludedLabels.contains(text) &&
           !text.hasPrefix("Explore ") && // Filter out "Explore X" artist page labels
           !text.hasPrefix("Songs by ") && // Filter out "Songs by X" recommendation labels
           !text.hasPrefix("Similar to ") && // Filter out "Similar to X" labels
           !text.contains("–") && !text.contains("—") && // Filter out date ranges like "Apr 10 – Aug 4"
           text.range(of: "^-?\\d+:\\d+$", options: .regularExpression) == nil && // Filter out timestamps like "0:00", "-2:47", "3:45"
           text.range(of: "\\d+\\s+(event|concert|show|tour)", options: [.regularExpression, .caseInsensitive]) == nil { // Filter out "19 events", "5 concerts"
            let fontSize = label.font?.pointSize ?? 0
            allLabels.append((text, fontSize, label.frame.origin.y, className))
        }
        
        // Recurse into subviews (limit depth)
        if depth < 20 {
            for subview in view.subviews {
                searchView(subview, depth: depth + 1)
            }
        }
    }
    
    searchView(window)
    
    NSLog("[EeveeSpotify] 🔍 Found \(allLabels.count) total labels")
    
    // Filter to only labels with reasonable font sizes (> 10pt) and unique text
    var seenTexts = Set<String>()
    let filteredLabels = allLabels.filter { label in
        let isNewText = !seenTexts.contains(label.text)
        if isNewText {
            seenTexts.insert(label.text)
        }
        return label.fontSize > 10.0 && isNewText
    }
    
    NSLog("[EeveeSpotify] 🔍 After filtering: \(filteredLabels.count) unique labels")
    
    // Strategy: Track title is usually in a larger font than artist
    // Sort by font size (descending) then by Y position (ascending)
    let sorted = filteredLabels.sorted { 
        if $0.fontSize != $1.fontSize {
            return $0.fontSize > $1.fontSize
        }
        return $0.y < $1.y
    }
    
    // Take the two largest/highest labels as likely candidates
    if sorted.count >= 2 {
        let title = sorted[0].text
        let artist = sorted[1].text
        
        NSLog("[EeveeSpotify] 🎯 Selected title: '\(title)' (size: \(sorted[0].fontSize))")
        NSLog("[EeveeSpotify] 🎯 Selected artist: '\(artist)' (size: \(sorted[1].fontSize))")
        
        return (title, artist)
    } else if sorted.count == 1 {
        NSLog("[EeveeSpotify] ⚠️ Only found one label: '\(sorted[0].text)'")
        return nil // Don't use if we only find one
    }
    
    NSLog("[EeveeSpotify] ❌ No suitable labels found")
    return nil
}

// Try to hook into NPVScrollViewController to capture track from scrollViewModel
class V91NPVScrollViewControllerMetadataHook: ClassHook<NSObject> {
    typealias Group = V91LyricsGroup
    static var targetName = "NowPlaying_ScrollImpl.NPVScrollViewController"
    
    // Hook viewWillAppear to try extracting track info from ivars
    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        
        NSLog("[EeveeSpotify] 🔍 V91 NPVScrollViewController viewWillAppear called")
        
        // Try to search view hierarchy
        if let info = searchViewHierarchyForTrackInfo() {
            capturedTrackTitle = info.title
            capturedArtistName = info.artist
            NSLog("[EeveeSpotify] ✅ Captured track info from view hierarchy!")
        }
    }
}
