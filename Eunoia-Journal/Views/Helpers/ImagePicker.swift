import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Photos

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let selectionLimit: Int
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .compatible
        
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
            super.init()
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                picker.dismiss(animated: true)
            }
            
            guard !results.isEmpty else { return }
            
            let dispatchGroup = DispatchGroup()
            var loadedImages = [UIImage]()
            
            for result in results {
                dispatchGroup.enter()
                
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                        defer { dispatchGroup.leave() }
                        
                        guard let self = self else { return }
                        
                        if let error = error {
                            print("Fehler beim direkten Laden des Bildes: \(error)")
                            return
                        }
                        
                        if let image = image as? UIImage {
                            let processedImage = self.processImage(image)
                            loadedImages.append(processedImage)
                        }
                    }
                } else if let identifier = result.assetIdentifier {
                    let options = PHImageRequestOptions()
                    options.isNetworkAccessAllowed = true
                    options.deliveryMode = .highQualityFormat
                    options.resizeMode = .exact
                    options.isSynchronous = false
                    
                    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                    if let asset = assets.firstObject {
                        PHImageManager.default().requestImage(
                            for: asset,
                            targetSize: PHImageManagerMaximumSize,
                            contentMode: .default,
                            options: options
                        ) { [weak self] image, info in
                            defer { dispatchGroup.leave() }
                            
                            guard let self = self, let image = image else { return }
                            
                            let processedImage = self.processImage(image)
                            loadedImages.append(processedImage)
                        }
                    } else {
                        dispatchGroup.leave()
                    }
                } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                        defer { dispatchGroup.leave() }
                        
                        guard let self = self else { return }
                        
                        if let error = error {
                            print("Fehler beim Laden der Bild-URL: \(error)")
                            return
                        }
                        
                        guard let url = url else {
                            print("Keine URL erhalten")
                            return
                        }
                        
                        do {
                            let imageData = try Data(contentsOf: url)
                            if let image = UIImage(data: imageData) {
                                let processedImage = self.processImage(image)
                                loadedImages.append(processedImage)
                            }
                        } catch {
                            print("Fehler beim Laden der Bild-Daten: \(error)")
                        }
                    }
                } else {
                    print("Keine Methode zum Laden des Bildes verfügbar")
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                
                if loadedImages.isEmpty {
                    print("Keine Bilder konnten verarbeitet werden")
                } else {
                    let sortedImages = loadedImages.sorted { lhs, rhs in
                        let lhsSize = lhs.size.width * lhs.size.height
                        let rhsSize = rhs.size.width * rhs.size.height
                        return lhsSize > rhsSize
                    }
                    
                    self.parent.selectedImages = sortedImages
                    print("Erfolgreich \(sortedImages.count) Bilder geladen")
                }
            }
        }
        
        private func processImage(_ image: UIImage) -> UIImage {
            let maxDimension: CGFloat = 2048.0
            
            if image.size.width > maxDimension || image.size.height > maxDimension {
                let scale = maxDimension / max(image.size.width, image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                
                return autoreleasepool { () -> UIImage in
                    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                    defer { UIGraphicsEndImageContext() }
                    
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                    guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
                        return image
                    }
                    
                    guard let jpegData = resizedImage.jpegData(compressionQuality: 0.7),
                          let compressedImage = UIImage(data: jpegData) else {
                        return resizedImage
                    }
                    
                    return compressedImage
                }
            } else {
                return autoreleasepool { () -> UIImage in
                    guard let jpegData = image.jpegData(compressionQuality: 0.7),
                          let compressedImage = UIImage(data: jpegData) else {
                        return image
                    }
                    
                    return compressedImage
                }
            }
        }
    }
} 