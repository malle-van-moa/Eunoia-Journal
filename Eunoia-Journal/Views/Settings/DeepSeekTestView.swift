import SwiftUI
import OSLog

struct DeepSeekTestView: View {
    @State private var prompt: String = "Erkläre in einem Satz, was Swift ist."
    @State private var result: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var apiKey: String = ""
    @State private var showApiKey: Bool = false
    
    private let logger = Logger(subsystem: "com.eunoia.journal", category: "DeepSeekTestView")
    
    var body: some View {
        Form {
            Section(header: Text("API-Key")) {
                HStack {
                    if showApiKey {
                        TextField("API-Key", text: $apiKey)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("API-Key", text: $apiKey)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    Button(action: {
                        showApiKey.toggle()
                    }) {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                }
                
                Button("API-Key speichern") {
                    if !apiKey.isEmpty {
                        let success = APIKeys.saveDeepSeekKey(apiKey)
                        if success {
                            logger.debug("API-Key erfolgreich gespeichert")
                        } else {
                            logger.error("Fehler beim Speichern des API-Keys")
                        }
                    }
                }
                .disabled(apiKey.isEmpty)
            }
            
            Section(header: Text("Prompt")) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 100)
                    .disabled(isLoading)
            }
            
            Section {
                Button(action: {
                    testDeepSeek()
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Generieren")
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(prompt.isEmpty || isLoading)
            }
            
            if !result.isEmpty {
                Section(header: Text("Ergebnis")) {
                    Text(result)
                        .padding()
                }
            }
            
            if let error = errorMessage {
                Section(header: Text("Fehler")) {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            
            Section(header: Text("Einfacher Test")) {
                Button("DeepSeek-Integration testen") {
                    testSimpleIntegration()
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle("DeepSeek Test")
        .onAppear {
            // Lade den gespeicherten API-Key
            if let key = APIKeys.loadAPIKey(forIdentifier: "com.eunoia.deepseek.apikey") {
                apiKey = key
            }
        }
    }
    
    private func testDeepSeek() {
        guard !prompt.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let generatedText = try await DeepSeekService.shared.generateText(prompt: prompt)
                DispatchQueue.main.async {
                    self.result = generatedText
                    self.isLoading = false
                }
            } catch {
                logger.error("DeepSeek-Fehler: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Fehler: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func testSimpleIntegration() {
        isLoading = true
        errorMessage = nil
        
        Task {
            let testResult = await DeepSeekService.shared.testDeepSeekIntegration()
            DispatchQueue.main.async {
                self.result = testResult
                self.isLoading = false
            }
        }
    }
}

#Preview {
    NavigationView {
        DeepSeekTestView()
    }
} 