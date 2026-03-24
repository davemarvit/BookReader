# BookReader iOS App Specification

## Core Identity
BookReader is a premium, offline-capable iOS SwiftUI Audiobook Player. The application is strictly **Audio-First**; while it renders EPUB text visually, every architectural decision is engineered to prioritize the audio-listening experience, pipeline stability, and driving/commuting use cases over visual e-reading. 

## Tech Stack
- **Language**: Swift 6 (iOS 15.0+ Deployment Target)
- **UI Framework**: Native SwiftUI
- **Audio Frameworks**: `AVFoundation` (`AVQueuePlayer`, `AVSpeechSynthesizer`), `MediaPlayer` (`MPRemoteCommandCenter`, `MPNowPlayingInfoCenter`)
- **Dependencies**: `ZIPFoundation` (for native EPUB unarchiving)

---

## 1. Data Models & State (`LibraryManager.swift`)
The app utilizes a strictly local, strictly private sandbox library architecture, completely independent of iCloud syncing to save bandwidth.

- **`BookMetadata` Struct**: Tracks `UUID`, `title`, `author`, `filename`, `coverFilename`, `lastParagraphIndex` (for progress tracking), and `chapters: [Chapter]`.
- **`LibraryManager` (ObservableObject)**:
  - Manages the `library.json` master index in the iOS Document Directory.
  - Automatically unzips and clones incoming user files (`.epub`, `.pdf`, `.txt`) from the iOS Document Picker (Files App) into the app's persistent sandbox layout. 
  - Handles parsing initialization routing and Cover Image physical extraction logic.

## 2. Parsing Engine (`DocumentParser.swift`)
Because the Audio Engine requires raw strings to synthesize speech safely, the `DocumentParser` acts as a heavy-duty sanitation engine rather than a layout formatter.

- **EPUB Deconstruction**: Natively unzips the `.epub` file using `ZIPFoundation`, hunts down `META-INF/container.xml`, discovers the root OPF file, and structurally aligns the `<spine>` and `<manifest>` maps.
- **Smart Front-Matter Skipping**: The parser evaluates the spine `idrefs` against a structural blacklist (`cover, title, copy, toc, dedic, ack`). It calculates the `initialParagraphIndex` by identifying the *first spine element* that does not match this blacklist, effectively automatically skipping the user to "Chapter 1".
- **Chapter Extraction**: Table of Contents (`chapters: [Chapter]`) are synthesized mathematically. The engine records the starting string index of each structurally distinct HTML file in the spine, effectively generating reliable chapter points without parsing fragile `.ncx` files.
- **HTML Extermination**: Employs Regex to obliterate all `<i>`, `<b>`, `<p>`, and inline CSS styling to extract raw plaintext data. Inline images are explicitly stripped, as they break TTS paragraph arrays. Returns `ParsedDocument(text: String, author: String, chapters: [Chapter], initialParagraphIndex: Int)`.

## 3. The Audio Pipeline (`AudioController.swift`)
This is the `ObservableObject` crown jewel of the app, ensuring perfectly gapless background audio synthesis. The "Atomic Unit" of the app is a **Paragraph** (a `String` block).

- **Google Mode (Premium)**: Hits the Google Cloud Text-to-Speech API (`GoogleTTSClient.swift`).
  - **Queue Pipeline**: Since the Google API returns asynchronous blocks of audio, the system constructs local `URL` cache files and mounts them into an `AVQueuePlayer`.
  - **Lookahead Buffering**: A recursive Task ensures the `AVQueuePlayer` always has exactly 5 paragraphs pre-cached and stacked in the local queue. As an item finishes playing, it is seamlessly replaced by a background fetch task guaranteeing gapless playback on cellular networks. 
- **Apple Offline Mode**: Uses local `AVSpeechSynthesizer`. Purely strings executed sequentially. Free and 100% offline.
- **Smart Rewind**: An invisible feature trapping `AVQueuePlayer.pause()`. If the user pauses for >30.0 seconds, the engine generates a `CMTime` shift of `-3.0` seconds upon resuming, natively scrolling back the audio buffer so the user regains contextual framing.
- **Pseudo-Time Map Seeking**: The `skip(bySeconds: Double)` mapping. Instead of seeking inside a volatile asynchronous audio chunk, the engine calculates a paragraph boundary index `(15 chars/sec * activePlaybackRate)` to find exactly which chunk represents +30 or -15 seconds of time, landing cleanly at the start of the required paragraph.
- **Lock Screen Integration**: Exports the EPUB's `coverImage` via `MPMediaItemPropertyArtwork` and maps physical volume steering wheel / CarPlay inputs to the time-seek algorithm via `MPRemoteCommandCenter`.

## 4. Visualization & UI (`ReaderView.swift` & `LibraryView.swift`)
- **`LibraryView`**: A SwiftUI grid/list rendering `BookMetadata` covers next to a computed circular Progress Ring mapping `book.lastParagraphIndex / totalParagraphs`.
- **`ReaderView`**: 
  - **Text Rendering**: A `ScrollViewReader` containing a `LazyVStack` mapping `id: index`. 
  - **Playback Controls**: Features native 15-second backward, 30-second backward, 15-second forward, and 30-second forward skip buttons replacing rigid paragraph-hopping.
  - **Native Syncing**: As the `AudioController` naturally increments its `currentParagraphIndex`, SwiftUI automatically jumps the ScrollView target and highlights the corresponding paragraph cell yellow organically.
  - **Tap-To-Play**: The UI allows a user to physically tap any rendered paragraph, which passes `index` into the AudioController and forces an instant Engine pipeline flush and rewrite.
  - **Customizable Appearance**: Native support for Dynamic Type, Fonts (System/Serif/Monospace/Rounded), and Color Schemes (`Default`, `Light`, `Dark`, `Sepia`, `Charcoal`).
  - **Sleep Timer**: Runs a standalone `Timer` loop inside the Audio Controller bridging a countdown overlay inside `ReaderControlsView`.
  - **Table of Contents Sheet**: Surfaces the structured chapters array in a searchable `.sheet`.

## 5. Secondary Systems
- **`SettingsManager.swift`**: Controls user defaults for Google API Key storage, active theme selection, active font selection, offline/online voice toggle preferences.
- **`StatsManager.swift`**: Logs cumulative playback seconds across the user's lifetime, calculating discrete buckets for `Today`, `This Week`, `This Month`, and `All Time` reading progress.
- **`HelpView.swift`**: A robust native iOS List indexing documentation on every feature natively accessible to the application.
