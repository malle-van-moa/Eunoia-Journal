import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let selectionLimit: Int
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        
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
        private var isProcessingImages = false
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !isProcessingImages else { return }
            isProcessingImages = true
            
            let dispatchGroup = DispatchGroup()
            var images: [UIImage] = []
            var errors: [Error] = []
            
            for result in results {
                dispatchGroup.enter()
                
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                        defer { dispatchGroup.leave() }
                        
                        if let error = error {
                            print("Fehler beim Laden des Bildes: \(error)")
                            errors.append(error)
                            return
                        }
                        
                        if let image = image as? UIImage {
                            // Komprimiere das Bild auf eine maximale Größe von 2048x2048 Pixeln
                            let maxDimension: CGFloat = 2048.0
                            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
                            
                            if scale < 1.0 {
                                let newSize = CGSize(
                                    width: image.size.width * scale,
                                    height: image.size.height * scale
                                )
                                
                                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                                image.draw(in: CGRect(origin: .zero, size: newSize))
                                let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
                                UIGraphicsEndImageContext()
                                
                                if let scaledImage = scaledImage {
                                    images.append(scaledImage)
                                } else {
                                    images.append(image)
                                }
                            } else {
                                images.append(image)
                            }
                        }
                    }
                } else {
                    dispatchGroup.leave()
                    errors.append(NSError(domain: "ImagePicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bildformat nicht unterstützt"]))
                }
            }
            
            dispatchGroup.notify(queue: .main) { [weak self] in
                self?.parent.selectedImages = images
                self?.isProcessingImages = false
                
                if !errors.isEmpty {
                    print("Einige Bilder konnten nicht geladen werden: \(errors)")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    picker.dismiss(animated: true)
                }
            }
        }
    }
} 