import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let selectionLimit: Int
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current
        
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
        private var processingQueue = DispatchQueue(label: "com.eunoia.imageProcessing", qos: .userInitiated, attributes: .concurrent)
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard !results.isEmpty else { return }
            
            let semaphore = DispatchSemaphore(value: 0)
            var processedImages: [UIImage] = []
            
            var processedCount = 0
            let totalCount = results.count
            
            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { 
                    processedCount += 1
                    if processedCount == totalCount {
                        semaphore.signal()
                    }
                    continue 
                }
                
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] (object, error) in
                    defer {
                        processedCount += 1
                        if processedCount == totalCount {
                            semaphore.signal()
                        }
                    }
                    
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Fehler beim Laden des Bildes: \(error)")
                        return
                    }
                    
                    guard let image = object as? UIImage else {
                        print("Konnte Objekt nicht als UIImage laden")
                        return
                    }
                    
                    let processedImage = self.processImage(image)
                    processedImages.append(processedImage)
                }
            }
            
            self.processingQueue.async {
                let timeout = DispatchTime.now() + .seconds(30)
                _ = semaphore.wait(timeout: timeout)
                
                DispatchQueue.main.async {
                    let sortedImages = processedImages.sorted {
                        $0.size.width * $0.size.height > $1.size.width * $1.size.height
                    }
                    
                    self.parent.selectedImages.append(contentsOf: sortedImages)
                }
            }
        }
        
        private func processImage(_ image: UIImage) -> UIImage {
            let maxDimension: CGFloat = 1024.0
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
            
            if scale < 1.0 {
                let newSize = CGSize(
                    width: image.size.width * scale,
                    height: image.size.height * scale
                )
                
                return autoreleasepool { () -> UIImage in
                    UIGraphicsBeginImageContextWithOptions(newSize, false, 0.7)
                    defer { UIGraphicsEndImageContext() }
                    
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                    guard let scaledImage = UIGraphicsGetImageFromCurrentImageContext() else {
                        return image
                    }
                    
                    guard let jpegData = scaledImage.jpegData(compressionQuality: 0.7),
                          let compressedImage = UIImage(data: jpegData) else {
                        return scaledImage
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