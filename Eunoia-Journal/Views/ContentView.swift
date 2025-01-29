//
//  ContentView.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//

import SwiftUI

struct ContentView: View {
    let persistenceController = PersistenceController.shared
    
    var body: some View {
        Button("📌 Eintrag in Core Data speichern") {
                       persistenceController.saveEntryLocally(
                           title: "Test-Tagebucheintrag",
                           content: "Heute war ein schöner Tag!",
                           tags: ["happy", "reflexion"],
                           images: []
                       )
                   }
    }
}

#Preview {
    ContentView()
}
