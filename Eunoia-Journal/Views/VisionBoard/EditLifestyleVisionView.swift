import SwiftUI

struct EditLifestyleVisionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VisionBoardViewModel
    
    @State private var dailyRoutine = ""
    @State private var livingEnvironment = ""
    @State private var workLife = ""
    @State private var relationships = ""
    @State private var hobbies = ""
    @State private var health = ""
    
    init(viewModel: VisionBoardViewModel) {
        self.viewModel = viewModel
        _dailyRoutine = State(initialValue: viewModel.visionBoard?.lifestyleVision.dailyRoutine ?? "")
        _livingEnvironment = State(initialValue: viewModel.visionBoard?.lifestyleVision.livingEnvironment ?? "")
        _workLife = State(initialValue: viewModel.visionBoard?.lifestyleVision.workLife ?? "")
        _relationships = State(initialValue: viewModel.visionBoard?.lifestyleVision.relationships ?? "")
        _hobbies = State(initialValue: viewModel.visionBoard?.lifestyleVision.hobbies ?? "")
        _health = State(initialValue: viewModel.visionBoard?.lifestyleVision.health ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tagesablauf")) {
                    TextEditor(text: $dailyRoutine)
                        .frame(height: 100)
                }
                
                Section(header: Text("Wohnumgebung")) {
                    TextEditor(text: $livingEnvironment)
                        .frame(height: 100)
                }
                
                Section(header: Text("Arbeitsleben")) {
                    TextEditor(text: $workLife)
                        .frame(height: 100)
                }
                
                Section(header: Text("Beziehungen")) {
                    TextEditor(text: $relationships)
                        .frame(height: 100)
                }
                
                Section(header: Text("Hobbys & Freizeit")) {
                    TextEditor(text: $hobbies)
                        .frame(height: 100)
                }
                
                Section(header: Text("Gesundheit & Wohlbefinden")) {
                    TextEditor(text: $health)
                        .frame(height: 100)
                }
            }
            .navigationTitle("Lifestyle Vision")
            .navigationBarItems(
                leading: Button("Abbrechen") {
                    dismiss()
                },
                trailing: Button("Speichern") {
                    let vision = LifestyleVision(
                        dailyRoutine: dailyRoutine,
                        livingEnvironment: livingEnvironment,
                        workLife: workLife,
                        relationships: relationships,
                        hobbies: hobbies,
                        health: health
                    )
                    viewModel.updateLifestyleVision(vision)
                    dismiss()
                }
            )
        }
    }
} 