import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section(header: Text("Library & Organization")) {
                NavigationLink(destination: TextHelpView(title: "Importing Books", content: "To add new books to your library:\n\n1. Go to the **Library** tab at the bottom of the screen.\n2. Tap the **+ (Plus)** button in the top right corner.\n3. Using the iOS Document Picker, select any .epub, .pdf, or .txt file from your iCloud Drive or 'On My iPhone' storage.\n\nThe app will instantly parse the text and add the book to your local library list.")) {
                    Label("Importing Books", systemImage: "square.and.arrow.down")
                }
                
                NavigationLink(destination: TextHelpView(title: "Tracking Progress", content: "**Reading Progress Rings**\n\nNext to every book in your Library list, you will see a circular pie chart (progress ring).\n\n- For the book **currently loaded in the player**, the ring reflects the live playback position — it updates in real time as audio advances or when you drag the progress slider.\n- For all other books, the ring shows your last saved position.\n\nYour progress is continuously saved in the background. If you leave a book and come back later, it will resume exactly where you left off.")) {
                    Label("Tracking Progress", systemImage: "chart.pie.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Reading Statistics", content: "**Cumulative Listening Time**\n\nThe app automatically tracks exactly how much time you spend listening to your books. You can view your total listening times for Today, This Week, This Month, This Year, and All Time by navigating to the **Settings** tab.\n\n**Resetting Your Stats**\nIf you ever want to clear your historical listening times, you can tap the red 'Reset Reading Stats' button in the Settings menu. \n\n*Note: Resetting your cumulative listening stats will NOT erase or affect your bookmarks, reading progress rings, or your current position inside any of your books!*")) {
                    Label("Reading Statistics", systemImage: "clock.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Deleting Books", content: "To remove a book from your device permanently:\n\n1. Go to the **Library** tab.\n2. **Swipe left** across the book row.\n3. Tap the red **Delete** button.\n4. Confirm in the dialog.\n\nThe book file, cover image, and all metadata are removed immediately. This action cannot be undone.")) {
                    Label("Deleting Books", systemImage: "trash.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Searching & Tags", content: "**Library Search**\n\nPull down on the Library list to reveal the search bar. Type any word to filter books by:\n- **Title**\n- **Author**\n- **Tags** (including auto-extracted keywords)\n\n**Tags & Keywords**\n\nWhen you import a book, the app automatically extracts meaningful keywords from its content using on-device natural language processing (lemmatization + term frequency). These keywords appear as tags in the Book Details screen.\n\nYou can edit, add, or remove tags at any time in Edit mode. To regenerate them — for example if you accidentally deleted some — tap the **✨ Re-extract Tags** button in Edit mode. The app will re-read the book and repopulate the tags field in the background.")) {
                    Label("Searching & Tags", systemImage: "tag.fill")
                }
            }
            
            Section(header: Text("Reading & Playback")) {
                NavigationLink(destination: TextHelpView(title: "Playback & Speed Control", content: "**Standard Controls**\nWhen you open a book by tapping it in your Library, you will see a set of playback controls at the bottom of the screen. You can play, pause, or skip forward/backward by 1 or 5 paragraphs using the chevron arrows.\n\n**Adjusting Playback Speed**\nThe playback speed slider is located at the very bottom of the reading view, flanked by a Tortoise (slower) and a Hare (faster) icon.\n\nSimply drag the slider to fine-tune the narrator's speed anywhere from **0.5x up to 4.0x**. Speed adjustments take effect immediately, making it easy to skim dense text or slow down for careful listening.\n\n**Lock Screen Controls**\nWhen you lock your phone, the app seamlessly broadcasts the book's cover art, title, and playback controls natively to the iOS Lock Screen so you can control it without opening the app!")) {
                    Label("Playback & Speed Control", systemImage: "play.circle.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Tap to Play", content: "You can instantly jump the audio to any point in the book simply by **tapping on the text** you want to hear.\n\nThe audio engine will immediately reposition itself and begin reading from the exact paragraph you touched. Natively synced highlighting will follow the narrator paragraph-by-paragraph as the book continues.")) {
                    Label("Tap to Play", systemImage: "hand.tap.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Sleep Timer", content: "To fall asleep while listening without losing your place:\n\n1. Tap the **Moon** icon in the top right corner of the reader view.\n2. Select a countdown timer for 15, 30, 45, or 60 minutes.\n3. The moon icon will visually transform into a countdown clock showing the remaining minutes.\n\nWhen the timer hits zero, the audio will automatically pause and save your exact location.")) {
                    Label("Sleep Timer", systemImage: "moon.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Smart Rewind", content: "If you pause your book to take a phone call, or disconnect from your car's Bluetooth, the app automatically stamps the exact time.\n\nWhen you resume playback after being paused for more than 30 seconds, the engine will **invisibly rewind the audio by 3 seconds**. This allows you to seamlessly hear the last few words of the previous sentence to regain your contextual footing before the new material starts!")) {
                    Label("Smart Rewind", systemImage: "gobackward.5")
                }
            }
            
            Section(header: Text("Appearance & Navigation")) {
                NavigationLink(destination: TextHelpView(title: "Customizing Appearance", content: "To adjust the visual layout of your book, tap the **'Aa'** icon in the top right corner of the reader view.\n\n**Themes / Backgrounds**\nYou can choose from five meticulously crafted color themes to reduce eye strain:\n- System Default\n- Light Mode\n- Dark Mode\n- Charcoal (Low-contrast dark grey)\n- Sepia (Warm, paper-like tone)\n\n**Typography**\nYou can also dynamically select your preferred typeface (System, Serif, Monospaced, or Rounded) and use the slider to increase or decrease the overall font size.")) {
                    Label("Fonts & Themes", systemImage: "textformat.size")
                }
                
                NavigationLink(destination: TextHelpView(title: "Table of Contents", content: "When you import an EPUB file, the parser automatically detects and skips front matter (cover pages, copyright notices, dedication, table of contents pages) so the audio begins near Chapter 1.\n\nFront matter is detected two ways:\n- **Filename**: spine items containing words like 'cover', 'title', 'toc', 'copyright', etc.\n- **Content length**: very short pages (3 or fewer short lines) are treated as cover/title pages regardless of filename.\n\nTo view the book's structure:\n1. Tap the **List** icon at the bottom left of the playback controls.\n2. A Table of Contents sheet will appear with all extracted chapter names.\n3. Tap any chapter to instantly jump the audio to that section.")) {
                    Label("Table of Contents", systemImage: "list.bullet")
                }
                
                NavigationLink(destination: TextHelpView(title: "Searching for Text", content: "Want to find a specific word or sentence in the book?\n\n1. Tap the **Magnifying Glass (Search)** icon in the top right corner of the reader view.\n2. Type your search phrase.\n3. The app will immediately jump to the first matching paragraph and highlight the text in yellow.\n4. You can use the up and down chevron arrows next to the search bar to jump between all the matches in the document.\n5. Tap 'Done' to close the search overlay. The audiobook will automatically resume from the paragraph you searched for.")) {
                    Label("Searching for Text", systemImage: "magnifyingglass")
                }
            }
            
            Section(header: Text("Book Details & Covers")) {
                NavigationLink(destination: TextHelpView(title: "Editing Book Info", content: "You can view and edit the full metadata of any book:\n\n1. Open the book from your Library.\n2. Tap the blue **'i' (Info)** button near the bottom right of the reading screen.\n3. This opens the **Book Details** page.\n4. Tap **Edit** to unlock all fields.\n\nEditable fields include:\n- **Title & Author**\n- **Summary** — the publisher's description, extracted from the EPUB metadata\n- **Tags** — auto-extracted keywords, fully editable\n- **Notes** — your personal notes\n\nTap **Done** to save all changes. Tap **✨ Re-extract Tags** to regenerate keywords from the book content if tags are missing or were accidentally deleted.")) {
                    Label("Editing Book Info", systemImage: "info.circle.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Changing Cover Artwork", content: "The app will attempt to extract the cover artwork embedded inside EPUB files automatically. However, you can choose to override it with your own image.\n\n1. Open the book and tap the **'i' (Info)** button to open the Book Details page.\n2. Tap **From Photos** to open your iOS Photo Library and select any image from your camera roll.\n3. Alternatively, tap **Paste URL** to paste a direct web link (URL) to any image online. The app will download it immediately.\n4. The new image will permanently replace the old cover both inside the app and everywhere in your Library list.")) {
                    Label("Changing Cover Artwork", systemImage: "photo.fill")
                }
            }
            
            Section(header: Text("Audio & Voices")) {
                NavigationLink(destination: TextHelpView(title: "Offline Listening (Apple Voices)", content: "You can listen to books entirely offline, without an internet connection, by using Apple's built-in system voices.\n\nTo enable offline listening:\n1. Go to the Settings tab.\n2. Under Voice Settings, select 'Apple System (Offline)'.\n3. Choose your preferred system voice from the dropdown.\n\nSince these voices are stored securely on your device, they work flawlessly on airplanes, on the subway, or anywhere without cell service. \n\n*Note: Apple System voices do not require an API Key.*")) {
                    Label("Offline Listening", systemImage: "wifi.slash")
                }
                
                NavigationLink(destination: TextHelpView(title: "Premium Audio (Google API)", content: "BookReader supports ultra-realistic, studio-quality voices powered by the Google Cloud Text-to-Speech API. \n\nBecause this is a premium cloud service, it requires an active internet connection to stream the generated audio over Wi-Fi or Cellular. To unlock this feature, you must provide your own private Google Cloud API Key. \n\nSee the 'How to get a Google API Key' section for a complete step-by-step guide.")) {
                    Label("Premium Audio", systemImage: "waveform")
                }
                
                NavigationLink(destination: GoogleAPIInstructionsView()) {
                    Label("Getting a Google API Key", systemImage: "key.fill")
                }
            }
        }
        .navigationTitle("Help & Info")
    }
}

struct TextHelpView: View {
    let title: String
    let content: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Using Markdown enabled Text parsing natively in iOS 15+
                Text(LocalizedStringKey(content))
                    .font(.body)
                    .lineSpacing(6)
                    .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GoogleAPIInstructionsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("To unlock premium Neural2 and Journey voices, follow these exact steps to generate your own private Google Cloud API Key:")
                    .font(.body)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("**1.** Go to **console.cloud.google.com** on a computer and sign in with any Google account.")
                    Text("**2.** Click the project dropdown at the top navigation bar and select **New Project**. Give it a name like 'BookReader' and click Create.")
                    Text("**3.** Open the left navigation menu (☰), and click on **APIs & Services > Library**.")
                    Text("**4.** Search for **Cloud Text-to-Speech API** and click the blue **Enable** button.")
                    Text("**5.** Go back to the left menu and click **APIs & Services > Credentials**.")
                    Text("**6.** Click **+ Create Credentials** at the top and select **API Key**.")
                    Text("**7.** Copy the generated API key. Open this app, go to Settings, and paste it into the 'Google API Key' field.")
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                
                Text("**Pricing & Free Tier**")
                    .font(.headline)
                    .padding(.top)
                
                Text("Google gives every developer account a massive free monthly quota (typically up to 1 million characters per month for premium voices, which is enough to read several full books). \n\nIf you exceed that quota, Google charges a few dollars per million characters. You must attach a billing account/credit card to your Google Cloud project to use the API, but you will not be charged a single cent as long as you stay under the generous free tier limit.")
                    .font(.body)
                    .lineSpacing(4)
                
                Text("**Choosing not to use Google API**")
                    .font(.headline)
                    .padding(.top)
                
                Text("If you prefer not to set up a Google Cloud account, simply leave the API key blank in Settings and switch the Speech Engine to **'Apple System (Offline)'**. The app will function perfectly and securely using your device's native voices.")
                    .font(.body)
                    .lineSpacing(4)
            }
            .padding()
        }
        .navigationTitle("API Setup Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
