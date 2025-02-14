import SwiftUI
import PhotosUI

struct ImagePickerButton: View {
    @Binding var selectedImages: [UIImage]
    let maxImages: Int
    
    @State private var showingImagePicker = false
    
    var body: some View {
        Button(action: {
            showingImagePicker = true
        }) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text("Bilder hinzufügen")
            }
            .foregroundColor(.blue)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                selectedImages: $selectedImages,
                selectionLimit: maxImages - selectedImages.count
            )
        }
    }
} 