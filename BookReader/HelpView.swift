import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section(header: Text("Library & Organization")) {
                NavigationLink(destination: TextHelpView(title: "Importing Books", content: "To add new books to your library:\n\n1. Go to the **Library** tab at the bottom of the screen.\n2. Tap the **+ (Plus)** button in the top right corner.\n3. Using the iOS Document Picker, select any .epub, .pdf, or .txt file from your iCloud Drive or 'On My iPhone' storage.\n\nThe app will instantly parse the text and add the book to your local library list.")) {
                    Label("Importing Books", systemImage: "square.and.arrow.down")
                }
                
                NavigationLink(destination: TextHelpView(title: "Tracking Progress", content: "**Reading Progress Rings**\n\nNext to every book in your Library list, you will see a circular pie chart (progress ring). This automatically fills up as you listen or advance through the book, giving you a quick visual indicator of exactly how much of the book you have completed.\n\nYour progress is continuously saved in the background. If you leave a book and come back a week later, it will resume exactly from the sentence where you left off.")) {
                    Label("Tracking Progress", systemImage: "chart.pie.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Deleting Books", content: "To remove a book from your device permanently:\n\n1. Go to the **Library** tab.\n2. Simply **swipe left** across the row of the book you wish to remove.\n3. Tap the red **Delete** button that appears.\n\n*Note: This will delete both the book file and any generated audio/metadata from your local storage. This action cannot be undone.*")) {
                    Label("Deleting Books", systemImage: "trash.fill")
                }
            }
            
            Section(header: Text("Reading & Playback")) {
                NavigationLink(destination: TextHelpView(title: "Playback & Speed Control", content: "**Standard Controls**\nWhen you open a book by tapping it in your Library, you will see a set of playback controls at the bottom of the screen. You can play, pause, or skip forward/backward by 1 or 5 paragraphs using the chevron arrows.\n\n**Adjusting Playback Speed**\nThe playback speed speed slider is located at the very bottom of the reading view, flanked by a Tortoise (slower) and a Hare (faster) icon.\n\nSimply drag the slider to fine-tune the narrator's speed anywhere from **0.5x up to 3.0x**. Speed adjustments take effect immediately, making it easy to skim dense text or slow down for careful listening.")) {
                    Label("Playback & Speed Control", systemImage: "play.circle.fill")
                }
                
                NavigationLink(destination: TextHelpView(title: "Searching for Text", content: "Want to find a specific word or sentence in the book?\n\n1. Tap the **Magnifying Glass (Search)** icon in the top right corner of the reader view.\n2. Type your search phrase.\n3. The app will immediately jump to the first matching paragraph and highlight the text in yellow.\n4. You can use the up and down chevron arrows next to the search bar to jump between all the matches in the document.\n5. Tap 'Done' to close the search overlay. The audiobook will automatically resume from the paragraph you searched for.")) {
                    Label("Searching for Text", systemImage: "magnifyingglass")
                }
            }
            
            Section(header: Text("Book Details & Covers")) {
                NavigationLink(destination: TextHelpView(title: "Editing Book Info", content: "You can view and edit the detailed metadata (author, title, notes) of any book in your library:\n\n1. Open the book from your Library.\n2. Tap the blue **'i' (Info)** button floating near the bottom right of the reading screen. \n3. This opens the **Book Details** page.\n4. Here you can edit the Title, author, or type personal notes.\n\nAny changes are saved automatically and immediately reflected in your Library list.")) {
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
