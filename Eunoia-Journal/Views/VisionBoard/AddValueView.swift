import SwiftUI

struct AddValueView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VisionBoardViewModel
    
    @State private var name = ""
    @State private var description = ""
    @State private var importance = 3
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Wert")) {
                    TextField("Name", text: $name)
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                Section(header: Text("Wichtigkeit")) {
                    Picker("Wichtigkeit", selection: $importance) {
                        ForEach(1...5, id: \.self) { rating in
                            HStack {
                                Text("\(rating)")
                                ForEach(0..<rating, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                }
                            }
                            .tag(rating)
                        }
                    }
                }
                
                Section(header: Text("Beispiele")) {
                    ForEach(PersonalValue.examples, id: \.self) { example in
                        Button(action: {
                            name = example
                        }) {
                            Text(example)
                        }
                    }
                }
            }
            .navigationTitle("Wert hinzufügen")
            .navigationBarItems(
                leading: Button("Abbrechen") {
                    dismiss()
                },
                trailing: Button("Speichern") {
                    let value = PersonalValue(
                        name: name,
                        description: description,
                        importance: importance
                    )
                    viewModel.addPersonalValue(value)
                    dismiss()
                }
                .disabled(name.isEmpty)
            )
        }
    }
} 