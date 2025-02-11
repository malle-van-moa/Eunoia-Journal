import SwiftUI

struct EditDesiredPersonalityView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VisionBoardViewModel
    
    @State private var traits = ""
    @State private var mindset = ""
    @State private var behaviors = ""
    @State private var skills = ""
    @State private var habits = ""
    @State private var growth = ""
    
    init(viewModel: VisionBoardViewModel) {
        self.viewModel = viewModel
        _traits = State(initialValue: viewModel.visionBoard?.desiredPersonality.traits ?? "")
        _mindset = State(initialValue: viewModel.visionBoard?.desiredPersonality.mindset ?? "")
        _behaviors = State(initialValue: viewModel.visionBoard?.desiredPersonality.behaviors ?? "")
        _skills = State(initialValue: viewModel.visionBoard?.desiredPersonality.skills ?? "")
        _habits = State(initialValue: viewModel.visionBoard?.desiredPersonality.habits ?? "")
        _growth = State(initialValue: viewModel.visionBoard?.desiredPersonality.growth ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Charaktereigenschaften")) {
                    TextEditor(text: $traits)
                        .frame(height: 100)
                }
                
                Section(header: Text("Denkweise & Einstellung")) {
                    TextEditor(text: $mindset)
                        .frame(height: 100)
                }
                
                Section(header: Text("Verhaltensweisen")) {
                    TextEditor(text: $behaviors)
                        .frame(height: 100)
                }
                
                Section(header: Text("Fähigkeiten & Kompetenzen")) {
                    TextEditor(text: $skills)
                        .frame(height: 100)
                }
                
                Section(header: Text("Gewohnheiten")) {
                    TextEditor(text: $habits)
                        .frame(height: 100)
                }
                
                Section(header: Text("Persönliche Entwicklung")) {
                    TextEditor(text: $growth)
                        .frame(height: 100)
                }
            }
            .navigationTitle("Persönlichkeit")
            .navigationBarItems(
                leading: Button("Abbrechen") {
                    dismiss()
                },
                trailing: Button("Speichern") {
                    let personality = DesiredPersonality(
                        traits: traits,
                        mindset: mindset,
                        behaviors: behaviors,
                        skills: skills,
                        habits: habits,
                        growth: growth
                    )
                    viewModel.updateDesiredPersonality(personality)
                    dismiss()
                }
            )
        }
    }
} 