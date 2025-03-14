import SwiftUI
import Foundation
import OSLog

struct APIKeySettingsView: View {
    @State private var openAIKey: String = ""
    @State private var deepSeekKey: String = ""
    @State private var showOpenAIKey: Bool = false
    @State private var showDeepSeekKey: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var showTestResultAlert: Bool = false
    @State private var testResult: String = ""
    @State private var selectedProvider: LLMProvider = LLMProvider.current
    @State private var isTestingDeepSeek: Bool = false
    
    private let logger = Logger(subsystem: "com.eunoia.journal", category: "APIKeySettingsView")
    
    var body: some View {
        Form {
            Section(header: Text("Aktiver KI-Anbieter")) {
                Picker("KI-Anbieter", selection: $selectedProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedProvider) { newValue in
                    LLMProvider.save(newValue)
                    logger.debug("KI-Anbieter geändert zu: \(newValue.rawValue)")
                }
            }
            
            Section(header: Text("OpenAI API-Key")) {
                HStack {
                    if showOpenAIKey {
                        TextField("API-Key", text: $openAIKey)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("API-Key", text: $openAIKey)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    Button(action: {
                        showOpenAIKey.toggle()
                    }) {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                }
                
                Button("OpenAI API-Key speichern") {
                    if !openAIKey.isEmpty {
                        let success = APIKeys.saveOpenAIKey(openAIKey)
                        if success {
                            logger.debug("OpenAI API-Key erfolgreich gespeichert")
                            showSavedAlert = true
                        } else {
                            logger.error("Fehler beim Speichern des OpenAI API-Keys")
                        }
                    }
                }
                .disabled(openAIKey.isEmpty)
            }
            
            Section(header: Text("DeepSeek API-Key")) {
                Text("Hinweis: Der DeepSeek API-Key muss mit 'Bearer ' beginnen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    if showDeepSeekKey {
                        TextField("API-Key", text: $deepSeekKey)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("API-Key", text: $deepSeekKey)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    Button(action: {
                        showDeepSeekKey.toggle()
                    }) {
                        Image(systemName: showDeepSeekKey ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                }
                
                Button("DeepSeek API-Key speichern") {
                    if !deepSeekKey.isEmpty {
                        // Stelle sicher, dass der Key mit "Bearer " beginnt
                        var keyToSave = deepSeekKey
                        if !keyToSave.hasPrefix("Bearer ") {
                            keyToSave = "Bearer " + keyToSave
                        }
                        
                        let success = APIKeys.saveDeepSeekKey(keyToSave)
                        if success {
                            logger.debug("DeepSeek API-Key erfolgreich gespeichert")
                            deepSeekKey = keyToSave // Aktualisiere das Textfeld
                            showSavedAlert = true
                        } else {
                            logger.error("Fehler beim Speichern des DeepSeek API-Keys")
                        }
                    }
                }
                .disabled(deepSeekKey.isEmpty)
            }
            
            Section(header: Text("Hinweis"), footer: Text("API-Keys werden sicher im Keychain gespeichert und nicht an Dritte weitergegeben.")) {
                Text("Die API-Keys werden benötigt, um die KI-Funktionen der App zu nutzen. Bitte beachte, dass die Nutzung der APIs kostenpflichtig sein kann.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Test")) {
                Button(action: {
                    testDeepSeekIntegration()
                }) {
                    if isTestingDeepSeek {
                        HStack {
                            Text("Teste DeepSeek-Integration...")
                            ProgressView()
                        }
                    } else {
                        Text("DeepSeek-Integration testen")
                    }
                }
                .disabled(isTestingDeepSeek)
                
                NavigationLink(destination: DeepSeekTestView()) {
                    Text("Erweiterte Tests")
                }
            }
        }
        .navigationTitle("API-Einstellungen")
        .onAppear {
            // Lade gespeicherte Werte
            selectedProvider = LLMProvider.current
            logger.debug("Aktueller KI-Anbieter: \(selectedProvider.rawValue)")
            
            // Lade API-Keys aus dem Keychain
            if let key = APIKeys.loadAPIKey(forIdentifier: "com.eunoia.openai.apikey") {
                openAIKey = key
                logger.debug("OpenAI API-Key geladen")
            } else {
                logger.debug("Kein OpenAI API-Key gefunden")
            }
            
            if let key = APIKeys.loadAPIKey(forIdentifier: "com.eunoia.deepseek.apikey") {
                deepSeekKey = key
                logger.debug("DeepSeek API-Key geladen")
            } else {
                logger.debug("Kein DeepSeek API-Key gefunden")
            }
        }
        .alert(isPresented: $showSavedAlert) {
            Alert(
                title: Text("Gespeichert"),
                message: Text("Der API-Key wurde erfolgreich gespeichert."),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("DeepSeek-Test", isPresented: $showTestResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(testResult)
        }
    }
    
    private func testDeepSeekIntegration() {
        isTestingDeepSeek = true
        
        Task {
            logger.debug("Starte DeepSeek-Integrationstest")
            testResult = await DeepSeekService.shared.testDeepSeekIntegration()
            
            DispatchQueue.main.async {
                self.isTestingDeepSeek = false
                self.showTestResultAlert = true
            }
        }
    }
}
