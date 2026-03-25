import SwiftUI
import PhotosUI

struct MetadataView: View {
    @ObservedObject var libraryManager: LibraryManager
    let book: BookMetadata
    
    var onRequestLibrary: (() -> Void)?
    var onRequestHome: (() -> Void)?
    
    @Environment(\.presentationMode) var presentationMode
    
    // Local state for editing fields
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var notes: String = ""
    @State private var summary: String = ""
    @State private var tags: String = ""
    @State private var isEditing: Bool = false
    @State private var isExtractingTags: Bool = false
    
    private var parsedTags: [String] {
        var results: [String] = []
        let rawTags = tags.components(separatedBy: ",")
        for tag in rawTags {
            let trimmed = tag.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                results.append(trimmed)
            }
        }
        return results
    }
    
    // Image Picker State
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    
    // Web URL State
    @State private var showingUrlAlert = false
    @State private var coverUrlString = ""
    @State private var isDownloading = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cover Image (Read Only for now)
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    if let coverURL = libraryManager.getCoverURL(for: book) {
                        AsyncImage(url: coverURL) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit)
                            case .failure:
                                fallbackCover
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(height: 300)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    } else {
                        fallbackCover
                    }
                }
                
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: {
                            showingImagePicker = true
                        }) {
                            Text("From Photos")
                                .font(.subheadline).bold()
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                        }
                        
                        Button(action: {
                            showingUrlAlert = true
                        }) {
                            Text("Paste URL")
                                .font(.subheadline).bold()
                                .foregroundColor(.green)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }
                    
                    if isEditing {
                        if book.coverFilename != nil {
                            Button(action: {
                                libraryManager.deleteCover(for: book)
                            }) {
                                Text("Delete Cover")
                                    .font(.subheadline).bold()
                                    .foregroundColor(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .alert("Paste Image URL", isPresented: $showingUrlAlert) {
                    TextField("https://...", text: $coverUrlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    
                    Button("Download", action: downloadCoverFromUrl)
                    Button("Cancel", role: .cancel) { coverUrlString = "" }
                } message: {
                    Text("Enter a direct link to an image (JPG/PNG).")
                }
                
                fieldsSection
                
            }
            .padding()
        }
        .navigationTitle(isEditing ? "Editing Book" : "Book Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleEditMode) {
                    Text(isEditing ? "Done" : "Edit")
                }
            }
        }
        .overlay(
            Group {
                if isDownloading {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Downloading...")
                            .font(.headline)
                    }
                    .padding(30)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 20)
                }
            }
        )
        .onAppear {
            // Initialize local state
            self.title = book.title
            self.author = book.author ?? ""
            self.notes = book.notes ?? ""
            self.summary = book.summary ?? ""
            self.tags = book.tags?.joined(separator: ", ") ?? ""
        }
    }
    
    @ViewBuilder
    private var fieldsSection: some View {
        Divider()
        
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                EditableInfoRow(label: "Title", text: $title)
                EditableInfoRow(label: "Author", text: $author)
            } else {
                InfoRow(label: "Title", value: title.isEmpty ? "Unknown" : title)
                InfoRow(label: "Author", value: author.isEmpty ? "Unknown" : author)
            }
            
            InfoRow(label: "Format", value: book.fileType.uppercased())
            InfoRow(label: "Added", value: formatDate(book.dateAdded))
            
            Divider()
            
            Group {
                Text("Summary").font(.headline)
                if isEditing {
                    TextEditor(text: $summary)
                        .frame(minHeight: 100)
                        .border(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                } else {
                    Text(summary.isEmpty ? "No summary available." : summary)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            Group {
                Text("Tags").font(.headline)
                if isEditing {
                    TextField("Comma separated tags...", text: $tags)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: reExtractTags) {
                        HStack(spacing: 6) {
                            if isExtractingTags {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Extracting...")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Re-extract Tags")
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.purple)
                        .padding(.vertical, 4)
                    }
                    .disabled(isExtractingTags)
                } else if !tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(parsedTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    Text("No tags.").font(.body).foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            Group {
                Text("Notes").font(.headline)
                if isEditing {
                    TextEditor(text: $notes)
                        .frame(height: 150)
                        .border(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                } else {
                    Text(notes.isEmpty ? "No notes added." : notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        
            Spacer()
        }
    }
    
    var fallbackCover: some View {
        Image(systemName: "text.book.closed.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 300)
            .foregroundColor(.gray)
            .padding()
    }
    
    private func reExtractTags() {
        isExtractingTags = true
        let bookURL = libraryManager.getBookURL(for: book)
        Task {
            // Run parsing on a background thread without capturing main-actor state
            let newTags: [String] = await Task.detached(priority: .userInitiated) {
                guard let parsed = DocumentParser.parse(url: bookURL) else { return [] }
                return KeywordExtractor.extract(from: parsed.text)
            }.value
            // Back on MainActor to update UI state
            if !newTags.isEmpty {
                tags = newTags.joined(separator: ", ")
            }
            isExtractingTags = false
        }
    }
    
    private func toggleEditMode() {
        if self.isEditing {
            self.libraryManager.updateTitle(for: self.book, title: self.title)
            self.libraryManager.updateAuthor(for: self.book, author: self.author)
            self.libraryManager.updateNotes(for: self.book, notes: self.notes)
            let tagsArray = self.parsedTags
            self.libraryManager.updateMetadataFields(for: self.book, summary: self.summary, tags: tagsArray.isEmpty ? nil : tagsArray)
        }
        withAnimation {
            self.isEditing.toggle()
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    func downloadCoverFromUrl() {
        guard let url = URL(string: coverUrlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        isDownloading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        libraryManager.updateCover(for: book, image: image)
                        coverUrlString = ""
                        isDownloading = false
                    }
                } else {
                    await MainActor.run { isDownloading = false }
                }
            } catch {
                print("Failed to download image: \(error.localizedDescription)")
                await MainActor.run { isDownloading = false }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

struct EditableInfoRow: View {
    let label: String
    @Binding var text: String
    
    var body: some View {
        HStack {
            Text(label + ":").foregroundColor(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async { self.parent.image = image as? UIImage }
                }
            }
        }
    }
}
