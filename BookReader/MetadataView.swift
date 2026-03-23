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
    
    // Image Picker State
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    
    // Web URL State
    @State private var showingUrlAlert = false
    @State private var coverUrlString = ""
    
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
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    EditableInfoRow(label: "Title", text: $title)
                        .onChange(of: title) { newValue in
                            libraryManager.updateTitle(for: book, title: newValue)
                        }
                    
                    EditableInfoRow(label: "Author", text: $author)
                        .onChange(of: author) { newValue in
                             libraryManager.updateAuthor(for: book, author: newValue)
                        }
                    
                    InfoRow(label: "Format", value: book.fileType.uppercased())
                    InfoRow(label: "Added", value: formatDate(book.dateAdded))
                    
                    Divider()
                    
                    Text("Notes")
                        .font(.headline)
                    
                    TextEditor(text: $notes)
                        .onChange(of: notes) { newValue in
                            libraryManager.updateNotes(for: book, notes: newValue)
                        }
                        .frame(height: 150)
                        .border(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("Book Details")

        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $inputImage)
        }
        .onChange(of: inputImage) { newImage in
            if let img = newImage {
                libraryManager.updateCover(for: book, image: img)
            }
        }
        .onAppear {
            // Initialize local state
            self.title = book.title
            self.author = book.author ?? ""
            self.notes = book.notes ?? ""
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
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    func downloadCoverFromUrl() {
        guard let url = URL(string: coverUrlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        libraryManager.updateCover(for: book, image: image)
                        coverUrlString = ""
                    }
                }
            } catch {
                print("Failed to download image: \(error.localizedDescription)")
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
