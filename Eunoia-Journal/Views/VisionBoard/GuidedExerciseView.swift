import SwiftUI

struct GuidedExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VisionBoardViewModel
    let exercise: VisionBoardViewModel.GuidedExercise
    
    @State private var currentStep = 0
    @State private var showingConfirmation = false
    
    // Personal Values
    @State private var valueName = ""
    @State private var valueDescription = ""
    @State private var valueImportance = 3
    
    // Goals
    @State private var goalTitle = ""
    @State private var goalDescription = ""
    @State private var goalCategory: Goal.Category = .personal
    @State private var goalDate = Date()
    @State private var goalPriority = 3
    
    // Lifestyle Vision
    @State private var dailyRoutine = ""
    @State private var livingEnvironment = ""
    @State private var workLife = ""
    @State private var relationships = ""
    @State private var hobbies = ""
    @State private var health = ""
    
    // Desired Personality
    @State private var traits = ""
    @State private var mindset = ""
    @State private var behaviors = ""
    @State private var skills = ""
    @State private var habits = ""
    @State private var growth = ""
    
    // Value Compass
    @State private var compassValues: [RadarChartEntry] = []
    @State private var currentValueName = ""
    @State private var currentValueImportance = 5
    @State private var currentValueSatisfaction = 5
    
    // Status für die Anzeige des benutzerdefinierten Wert-Formulars
    @State private var showCustomValueForm = false
    
    // Aktiv bearbeiteter Wert
    @State private var editingValueName: String? = nil
    
    // Temporäre Werte für die Bearbeitung
    @State private var tempImportance: Int = 5
    @State private var tempSatisfaction: Int = 5
    
    var body: some View {
        VStack {
            // Progress Bar
            ProgressView(value: Double(currentStep) / Double(totalSteps - 1))
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                .padding()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Exercise Content
                    switch exercise {
                    case .values:
                        PersonalValuesExercise(
                            step: currentStep,
                            name: $valueName,
                            description: $valueDescription,
                            importance: $valueImportance
                        )
                    case .goals:
                        GoalsExercise(
                            step: currentStep,
                            title: $goalTitle,
                            description: $goalDescription,
                            category: $goalCategory,
                            date: $goalDate,
                            priority: $goalPriority
                        )
                    case .lifestyle:
                        LifestyleExercise(
                            step: currentStep,
                            dailyRoutine: $dailyRoutine,
                            livingEnvironment: $livingEnvironment,
                            workLife: $workLife,
                            relationships: $relationships,
                            hobbies: $hobbies,
                            health: $health
                        )
                    case .personality:
                        PersonalityExercise(
                            step: currentStep,
                            traits: $traits,
                            mindset: $mindset,
                            behaviors: $behaviors,
                            skills: $skills,
                            habits: $habits,
                            growth: $growth
                        )
                    case .valueCompass:
                        ValueCompassExercise(
                            step: currentStep,
                            compassValues: $compassValues,
                            currentValueName: $currentValueName,
                            currentValueImportance: $currentValueImportance,
                            currentValueSatisfaction: $currentValueSatisfaction
                        )
                    }
                }
                .padding()
            }
            
            // Navigation Buttons
            HStack {
                if currentStep > 0 {
                    Button(LocalizedStringKey("Back")) {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                }
                
                Spacer()
                
                Button(currentStep == totalSteps - 1 ? LocalizedStringKey("Complete") : LocalizedStringKey("Next")) {
                    if currentStep == totalSteps - 1 {
                        completeExercise()
                    } else {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                }
                .disabled(!isStepValid)
            }
            .padding()
        }
        .navigationTitle(exercise.rawValue)
        .navigationBarItems(trailing: Button(LocalizedStringKey("Cancel")) {
            showingConfirmation = true
        })
        .alert(LocalizedStringKey("Cancel Exercise?"), isPresented: $showingConfirmation) {
            Button(LocalizedStringKey("Yes"), role: .destructive) {
                viewModel.currentExercise = nil
                dismiss()
            }
            Button(LocalizedStringKey("No"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("Your progress will be lost."))
        }
    }
    
    private var totalSteps: Int {
        switch exercise {
        case .values: return 3
        case .goals: return 5
        case .lifestyle: return 5
        case .personality: return 4
        case .valueCompass: return 4
        }
    }
    
    private var isStepValid: Bool {
        switch exercise {
        case .values:
            switch currentStep {
            case 0: return !valueName.isEmpty
            case 1: return !valueDescription.isEmpty
            default: return true
            }
        case .goals:
            switch currentStep {
            case 0: return !goalTitle.isEmpty
            case 1: return !goalDescription.isEmpty
            case 2: return true
            case 3: return true
            default: return true
            }
        case .lifestyle:
            switch currentStep {
            case 0: return !dailyRoutine.isEmpty
            case 1: return !livingEnvironment.isEmpty
            case 2: return !workLife.isEmpty
            case 3: return !relationships.isEmpty
            case 4: return !hobbies.isEmpty
            default: return !health.isEmpty
            }
        case .personality:
            switch currentStep {
            case 0: return !traits.isEmpty
            case 1: return !mindset.isEmpty
            case 2: return !behaviors.isEmpty
            case 3: return !skills.isEmpty
            default: return !habits.isEmpty
            }
        case .valueCompass:
            switch currentStep {
            case 0: return true // Einführungsschritt
            case 1: return compassValues.count >= 3 || showCustomValueForm // Mindestens 3 Werte erforderlich oder Formular geöffnet
            case 2: return compassValues.count >= 3 // Mindestens 3 Werte erforderlich
            default: return true
            }
        }
    }
    
    private func completeExercise() {
        switch exercise {
        case .values:
            let value = PersonalValue(
                name: valueName,
                description: valueDescription,
                importance: valueImportance
            )
            viewModel.addPersonalValue(value)
            
        case .goals:
            let goal = Goal(
                title: goalTitle,
                description: goalDescription,
                category: goalCategory,
                targetDate: goalDate,
                priority: goalPriority
            )
            viewModel.addGoal(goal)
            
        case .lifestyle:
            let vision = LifestyleVision(
                dailyRoutine: dailyRoutine,
                livingEnvironment: livingEnvironment,
                workLife: workLife,
                relationships: relationships,
                hobbies: hobbies,
                health: health
            )
            viewModel.updateLifestyleVision(vision)
            
        case .personality:
            let personality = DesiredPersonality(
                traits: traits,
                mindset: mindset,
                behaviors: behaviors,
                skills: skills,
                habits: habits,
                growth: growth
            )
            viewModel.updateDesiredPersonality(personality)
            
        case .valueCompass:
            viewModel.updateValueCompass(compassValues)
        }
        
        viewModel.completeExercise()
        dismiss()
    }
}

// MARK: - Exercise Views

struct PersonalValuesExercise: View {
    let step: Int
    @Binding var name: String
    @Binding var description: String
    @Binding var importance: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Wert benennen",
                    description: "Welchen persönlichen Wert möchtest du definieren?",
                    example: "Beispiel: Authentizität, Wachstum, Mitgefühl"
                )
                TextField("Name des Wertes", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case 1:
                ExercisePrompt(
                    title: "Wert beschreiben",
                    description: "Was bedeutet dieser Wert für dich? Wie beeinflusst er dein Handeln?",
                    example: "Beispiel: Authentisch zu sein bedeutet für mich..."
                )
                TextEditor(text: $description)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 2:
                ExercisePrompt(
                    title: "Wichtigkeit",
                    description: "Wie wichtig ist dir dieser Wert?",
                    example: ""
                )
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
                
            default:
                EmptyView()
            }
        }
    }
}

struct GoalsExercise: View {
    let step: Int
    @Binding var title: String
    @Binding var description: String
    @Binding var category: Goal.Category
    @Binding var date: Date
    @Binding var priority: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Ziel definieren",
                    description: "Was möchtest du erreichen?",
                    example: "Beispiel: Eine neue Sprache lernen"
                )
                TextField("Titel des Ziels", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case 1:
                ExercisePrompt(
                    title: "Ziel beschreiben",
                    description: "Beschreibe dein Ziel genauer. Was macht es bedeutsam für dich?",
                    example: "Beispiel: Ich möchte Spanisch lernen, um..."
                )
                TextEditor(text: $description)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 2:
                ExercisePrompt(
                    title: "Kategorie",
                    description: "In welchen Lebensbereich fällt dieses Ziel?",
                    example: ""
                )
                Picker("Kategorie", selection: $category) {
                    ForEach(Goal.Category.allCases, id: \.self) { category in
                        Text(category.localizedName)
                            .tag(category)
                    }
                }
                
            case 3:
                ExercisePrompt(
                    title: "Zieldatum",
                    description: "Bis wann möchtest du dieses Ziel erreichen?",
                    example: ""
                )
                DatePicker("Zieldatum", selection: $date, displayedComponents: .date)
                
            case 4:
                ExercisePrompt(
                    title: "Priorität",
                    description: "Wie wichtig ist dir dieses Ziel?",
                    example: ""
                )
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
                
            default:
                EmptyView()
            }
        }
    }
}

struct LifestyleExercise: View {
    let step: Int
    @Binding var dailyRoutine: String
    @Binding var livingEnvironment: String
    @Binding var workLife: String
    @Binding var relationships: String
    @Binding var hobbies: String
    @Binding var health: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Tagesablauf",
                    description: "Wie sieht dein idealer Tagesablauf aus?",
                    example: "Beispiel: Mein Tag beginnt mit..."
                )
                TextEditor(text: $dailyRoutine)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 1:
                ExercisePrompt(
                    title: "Wohnumgebung",
                    description: "Wie und wo möchtest du leben?",
                    example: "Beispiel: Ich lebe in einer ruhigen Gegend..."
                )
                TextEditor(text: $livingEnvironment)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 2:
                ExercisePrompt(
                    title: "Arbeitsleben",
                    description: "Wie sieht dein ideales Arbeitsleben aus?",
                    example: "Beispiel: Meine Arbeit ermöglicht mir..."
                )
                TextEditor(text: $workLife)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 3:
                ExercisePrompt(
                    title: "Beziehungen",
                    description: "Wie gestaltest du deine Beziehungen zu anderen?",
                    example: "Beispiel: Meine Beziehungen sind geprägt von..."
                )
                TextEditor(text: $relationships)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 4:
                ExercisePrompt(
                    title: "Hobbys & Freizeit",
                    description: "Wie verbringst du deine Freizeit?",
                    example: "Beispiel: In meiner Freizeit widme ich mich..."
                )
                TextEditor(text: $hobbies)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 5:
                ExercisePrompt(
                    title: "Gesundheit & Wohlbefinden",
                    description: "Wie sorgst du für deine Gesundheit und dein Wohlbefinden?",
                    example: "Beispiel: Ich achte auf meine Gesundheit indem..."
                )
                TextEditor(text: $health)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            default:
                EmptyView()
            }
        }
    }
}

struct PersonalityExercise: View {
    let step: Int
    @Binding var traits: String
    @Binding var mindset: String
    @Binding var behaviors: String
    @Binding var skills: String
    @Binding var habits: String
    @Binding var growth: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Charaktereigenschaften",
                    description: "Welche Eigenschaften möchtest du verkörpern?",
                    example: "Beispiel: Ich bin eine Person, die..."
                )
                TextEditor(text: $traits)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 1:
                ExercisePrompt(
                    title: "Denkweise & Einstellung",
                    description: "Wie möchtest du die Welt und dich selbst sehen?",
                    example: "Beispiel: Ich sehe Herausforderungen als..."
                )
                TextEditor(text: $mindset)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 2:
                ExercisePrompt(
                    title: "Verhaltensweisen",
                    description: "Wie möchtest du in verschiedenen Situationen handeln?",
                    example: "Beispiel: In schwierigen Situationen..."
                )
                TextEditor(text: $behaviors)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 3:
                ExercisePrompt(
                    title: "Fähigkeiten & Kompetenzen",
                    description: "Welche Fähigkeiten möchtest du entwickeln?",
                    example: "Beispiel: Ich möchte mich verbessern in..."
                )
                TextEditor(text: $skills)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 4:
                ExercisePrompt(
                    title: "Gewohnheiten",
                    description: "Welche Gewohnheiten möchtest du entwickeln?",
                    example: "Beispiel: Jeden Tag nehme ich mir Zeit für..."
                )
                TextEditor(text: $habits)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 5:
                ExercisePrompt(
                    title: "Persönliche Entwicklung",
                    description: "Wie möchtest du dich weiterentwickeln?",
                    example: "Beispiel: In den nächsten Jahren möchte ich..."
                )
                TextEditor(text: $growth)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            default:
                EmptyView()
            }
        }
    }
}

// ValueCompassExercise
struct ValueCompassExercise: View {
    let step: Int
    @Binding var compassValues: [RadarChartEntry]
    @Binding var currentValueName: String
    @Binding var currentValueImportance: Int
    @Binding var currentValueSatisfaction: Int
    
    // Vordefinierte Werte für den Wertekompass
    private let predefinedValues = [
        "Gesundheit und Wohlbefinden",
        "Familie und Beziehungen",
        "Freundschaft und soziale Kontakte",
        "Karriere und berufliche Erfüllung",
        "Finanzielle Sicherheit",
        "Persönliches Wachstum und Lernen",
        "Freiheit und Unabhängigkeit",
        "Kreativität und Selbstausdruck",
        "Spaß und Lebensfreude",
        "Spiritualität oder Sinnhaftigkeit",
        "Altruismus und soziales Engagement"
    ]
    
    // Status für die Anzeige des benutzerdefinierten Wert-Formulars
    @State private var showCustomValueForm = false
    
    // Aktiv bearbeiteter Wert
    @State private var editingValueName: String? = nil
    
    // Temporäre Werte für die Bearbeitung
    @State private var tempImportance: Int = 5
    @State private var tempSatisfaction: Int = 5
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Einführung zum Wertekompass",
                    description: "Der Wertekompass hilft dir, deine wichtigsten Werte zu identifizieren und zu visualisieren, wie zufrieden du mit ihrer Umsetzung in deinem Leben bist.",
                    example: "Bewerte jeden Wert nach seiner Wichtigkeit (1-10) und deiner aktuellen Zufriedenheit (1-10). Die Differenz zeigt dir, wo Handlungsbedarf besteht."
                )
                
                Text("So gehst du vor:")
                    .font(.headline)
                    .padding(.top, 10)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Wähle mindestens 3 Werte aus oder füge eigene hinzu (max. 8)")
                    Text("2. Bewerte jeden Wert nach Wichtigkeit (1-10)")
                    Text("3. Bewerte deine aktuelle Zufriedenheit (1-10)")
                    Text("4. Betrachte das Ergebnis und identifiziere Handlungsbedarf")
                }
                .padding(.leading)
                
            case 1:
                ExercisePrompt(
                    title: "Werte auswählen",
                    description: "Wähle wichtige Werte für deinen Kompass aus oder füge eigene hinzu. Du brauchst mindestens 3 Werte.",
                    example: ""
                )
                
                // Liste der vordefinierten Werte
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(predefinedValues, id: \.self) { value in
                            // Prüfen, ob der Wert bereits hinzugefügt wurde
                            let isSelected = compassValues.contains(where: { $0.name == value })
                            let isEditing = editingValueName == value
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: {
                                    if isSelected {
                                        if isEditing {
                                            // Bearbeitung beenden
                                            editingValueName = nil
                                        } else {
                                            // Bearbeitung starten
                                            editingValueName = value
                                            if let index = compassValues.firstIndex(where: { $0.name == value }) {
                                                let entry = compassValues[index]
                                                tempImportance = entry.importance
                                                tempSatisfaction = entry.satisfaction
                                            }
                                        }
                                    } else {
                                        // Wert hinzufügen mit Standardwerten
                                        let newValue = RadarChartEntry(
                                            name: value,
                                            importance: 5,
                                            satisfaction: 5
                                        )
                                        compassValues.append(newValue)
                                        
                                        // Direkt in Bearbeitungsmodus wechseln
                                        editingValueName = value
                                        tempImportance = 5
                                        tempSatisfaction = 5
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                            .foregroundColor(isSelected ? .purple : .gray)
                                        
                                        Text(value)
                                            .fontWeight(isSelected ? .bold : .regular)
                                            .foregroundColor(isSelected ? .primary : .primary)
                                        
                                        Spacer()
                                        
                                        if isSelected && !isEditing {
                                            // Zeige die aktuellen Werte an
                                            if let selectedValue = compassValues.first(where: { $0.name == value }) {
                                                HStack(spacing: 12) {
                                                    Text("W: \(selectedValue.importance)")
                                                        .foregroundColor(.blue)
                                                        .font(.caption)
                                                        .bold()
                                                    
                                                    Text("Z: \(selectedValue.satisfaction)")
                                                        .foregroundColor(.green)
                                                        .font(.caption)
                                                        .bold()
                                                }
                                            }
                                            
                                            // Löschen-Button
                                            Button(action: {
                                                compassValues.removeAll(where: { $0.name == value })
                                                if editingValueName == value {
                                                    editingValueName = nil
                                                }
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                                    .font(.caption)
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                // Bearbeitungsbereich, wenn dieser Wert bearbeitet wird
                                if isEditing {
                                    VStack(spacing: 12) {
                                        // Wichtigkeit-Slider
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("Wichtigkeit:")
                                                    .font(.subheadline)
                                                    .foregroundColor(.blue)
                                                
                                                Spacer()
                                                
                                                Text("\(tempImportance)")
                                                    .font(.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.blue)
                                                    .frame(width: 30, alignment: .trailing)
                                            }
                                            
                                            Slider(value: Binding(
                                                get: { Double(tempImportance) },
                                                set: { tempImportance = Int($0) }
                                            ), in: 1...10, step: 1)
                                            .accentColor(.blue)
                                        }
                                        
                                        // Zufriedenheit-Slider
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("Zufriedenheit:")
                                                    .font(.subheadline)
                                                    .foregroundColor(.green)
                                                
                                                Spacer()
                                                
                                                Text("\(tempSatisfaction)")
                                                    .font(.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.green)
                                                    .frame(width: 30, alignment: .trailing)
                                            }
                                            
                                            Slider(value: Binding(
                                                get: { Double(tempSatisfaction) },
                                                set: { tempSatisfaction = Int($0) }
                                            ), in: 1...10, step: 1)
                                            .accentColor(.green)
                                        }
                                        
                                        // Speichern-Button
                                        HStack {
                                            Spacer()
                                            
                                            Button(action: {
                                                // Werte speichern
                                                if let index = compassValues.firstIndex(where: { $0.name == value }) {
                                                    compassValues[index] = RadarChartEntry(
                                                        name: value,
                                                        importance: tempImportance,
                                                        satisfaction: tempSatisfaction
                                                    )
                                                }
                                                
                                                // Bearbeitungsmodus beenden
                                                editingValueName = nil
                                            }) {
                                                Text("Speichern")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.purple)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                                    .background(Color.purple.opacity(0.1))
                                                    .cornerRadius(8)
                                            }
                                        }
                                    }
                                    .padding(.leading, 30)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                                    .background(Color(.systemBackground).opacity(0.8))
                                    .cornerRadius(8)
                                    .transition(.opacity)
                                }
                            }
                            
                            Divider()
                        }
                        
                        // Button zum Hinzufügen eines eigenen Wertes
                        Button(action: {
                            currentValueName = ""
                            currentValueImportance = 5
                            currentValueSatisfaction = 5
                            showCustomValueForm = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.purple)
                                Text("Eigenen Wert hinzufügen")
                                    .foregroundColor(.purple)
                            }
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 20)
                }
                
                // Formular für benutzerdefinierte Werte
                if showCustomValueForm {
                    VStack(spacing: 15) {
                        Text("Neuen Wert hinzufügen")
                            .font(.headline)
                            .padding(.top, 10)
                        
                        TextField("Name des Wertes", text: $currentValueName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        // Wichtigkeit-Slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Wichtigkeit:")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                
                                Spacer()
                                
                                Text("\(currentValueImportance)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(currentValueImportance) },
                                set: { currentValueImportance = Int($0) }
                            ), in: 1...10, step: 1)
                            .accentColor(.blue)
                        }
                        
                        // Zufriedenheit-Slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Zufriedenheit:")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                
                                Spacer()
                                
                                Text("\(currentValueSatisfaction)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                    .frame(width: 30, alignment: .trailing)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(currentValueSatisfaction) },
                                set: { currentValueSatisfaction = Int($0) }
                            ), in: 1...10, step: 1)
                            .accentColor(.green)
                        }
                        
                        HStack {
                            Button(action: {
                                showCustomValueForm = false
                            }) {
                                Text("Abbrechen")
                                    .padding()
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                if !currentValueName.isEmpty {
                                    // Neuen Wert hinzufügen
                                    let newValue = RadarChartEntry(
                                        name: currentValueName,
                                        importance: currentValueImportance,
                                        satisfaction: currentValueSatisfaction
                                    )
                                    compassValues.append(newValue)
                                    
                                    // Formular zurücksetzen und schließen
                                    currentValueName = ""
                                    currentValueImportance = 5
                                    currentValueSatisfaction = 5
                                    showCustomValueForm = false
                                }
                            }) {
                                Text("Speichern")
                                    .foregroundColor(.purple)
                                    .padding()
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .disabled(currentValueName.isEmpty)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .padding(.vertical)
                }
                
                // Anzeige der ausgewählten Werte
                if !compassValues.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ausgewählte Werte (\(compassValues.count)):")
                            .font(.headline)
                            .padding(.top, 10)
                        
                        Text("Du benötigst mindestens 3 Werte für deinen Wertekompass.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
            case 2:
                ExercisePrompt(
                    title: "Dein Wertekompass",
                    description: "Hier ist die visuelle Darstellung deiner Werte.",
                    example: ""
                )
                
                if compassValues.count >= 3 {
                    RadarChartView(values: compassValues)
                        .padding(.vertical)
                } else {
                    Text("Bitte füge mindestens 3 Werte hinzu, um den Kompass anzuzeigen.")
                        .foregroundColor(.orange)
                        .padding()
                }
                
                Text("Werte mit größter Differenz:")
                    .font(.headline)
                    .padding(.top, 10)
                
                let sortedValues = compassValues.sorted(by: { $0.gap > $1.gap })
                let valuesToShow = sortedValues.prefix(3).filter { $0.gap > 0 }
                
                if valuesToShow.isEmpty {
                    Text("Alle Werte sind im Gleichgewicht!")
                        .foregroundColor(.green)
                        .padding()
                } else {
                    ForEach(Array(valuesToShow.enumerated()), id: \.element.id) { index, value in
                        HStack {
                            Text("\(index + 1). \(value.name)")
                                .fontWeight(.medium)
                            Spacer()
                            Text("Differenz: \(value.gap)")
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
            case 3:
                ExercisePrompt(
                    title: "Reflexion",
                    description: "Was sagt dir dein Wertekompass über dein Leben?",
                    example: ""
                )
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("Dein Wertekompass zeigt dir:")
                        .font(.headline)
                    
                    Text("• Welche Werte dir besonders wichtig sind")
                    Text("• Wie zufrieden du mit der Umsetzung dieser Werte bist")
                    Text("• Wo die größten Differenzen zwischen Wichtigkeit und Zufriedenheit bestehen")
                    
                    Text("Handlungsempfehlungen:")
                        .font(.headline)
                        .padding(.top, 10)
                    
                    Text("• Konzentriere dich auf die Werte mit der größten Differenz")
                    Text("• Überlege, welche konkreten Schritte du unternehmen kannst, um deine Zufriedenheit in diesen Bereichen zu erhöhen")
                    Text("• Nutze deinen Wertekompass als Entscheidungshilfe im Alltag")
                    
                    if compassValues.count >= 3 {
                        RadarChartView(values: compassValues)
                            .padding(.vertical)
                    }
                }
                
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Supporting Views

struct ExercisePrompt: View {
    let title: String
    let description: String
    let example: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !example.isEmpty {
                Text(example)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct DynamicList: View {
    @Binding var items: [String]
    
    var body: some View {
        VStack {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    TextField("Enter item", text: $items[index])
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    if items.count > 1 {
                        Button(action: {
                            items.remove(at: index)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            Button(action: {
                items.append("")
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Item")
                }
            }
            .foregroundColor(.blue)
        }
    }
}

struct DynamicInputField: View {
    let title: String
    @Binding var subject: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
            ZStack(alignment: .leading) {
                if subject.isEmpty {
                    Text("Enter your text here...")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4)
                }
                TextField("", text: $subject)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        overlay(
            ZStack(alignment: alignment) {
                if shouldShow {
                    placeholder()
                }
            }
        )
    }
}

#Preview {
    NavigationView {
        GuidedExerciseView(
            viewModel: VisionBoardViewModel(),
            exercise: .values
        )
    }
} 