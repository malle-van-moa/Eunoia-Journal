import SwiftUI

struct AddGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VisionBoardViewModel
    
    @State private var title = ""
    @State private var description = ""
    @State private var category: Goal.Category = .personal
    @State private var targetDate = Date()
    @State private var priority = 3
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Ziel")) {
                    TextField("Titel", text: $title)
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                Section(header: Text("Details")) {
                    Picker("Kategorie", selection: $category) {
                        ForEach(Goal.Category.allCases, id: \.self) { category in
                            Text(category.localizedName)
                                .tag(category)
                        }
                    }
                    
                    DatePicker("Zieldatum", selection: $targetDate, displayedComponents: .date)
                    
                    Picker("Priorität", selection: $priority) {
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
                    ForEach(category.examples, id: \.self) { example in
                        Button(action: {
                            title = example
                        }) {
                            Text(example)
                        }
                    }
                }
            }
            .navigationTitle("Ziel hinzufügen")
            .navigationBarItems(
                leading: Button("Abbrechen") {
                    dismiss()
                },
                trailing: Button("Speichern") {
                    let goal = Goal(
                        title: title,
                        description: description,
                        category: category,
                        targetDate: targetDate,
                        priority: priority
                    )
                    viewModel.addGoal(goal)
                    dismiss()
                }
                .disabled(title.isEmpty)
            )
        }
    }
} 