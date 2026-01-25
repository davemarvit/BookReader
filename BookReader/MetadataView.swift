import SwiftUI
import PhotosUI

struct MetadataView: View {
    @ObservedObject var libraryManager: LibraryManager
    var book: BookMetadata
    
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cover Image
                if let coverURL = libraryManager.getCoverURL(for: book) {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .empty: ProgressView()
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        case .failure:
                            Image(systemName: "text.book.closed.fill")
                                .resizable().aspectRatio(contentMode: .fit)
                        @unknown default: EmptyView()
                        }
                    }
                    .frame(height: 300)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                } else {
                    Image(systemName: "text.book.closed.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 300)
                        .foregroundColor(.gray)
                        .padding()
                }
                
                Button("Change Cover Image") {
                    showingImagePicker = true
                }
                .font(.headline)
                .padding()
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Title", value: book.title)
                    InfoRow(label: "Author", value: book.author ?? "Unknown")
                    InfoRow(label: "Format", value: book.fileType.uppercased())
                    InfoRow(label: "Paragraphs", value: "\(book.totalParagraphs ?? 0)")
                    InfoRow(label: "Added", value: formatDate(book.dateAdded))
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
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.body)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}
