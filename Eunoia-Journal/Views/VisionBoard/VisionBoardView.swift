import SwiftUI

// MARK: - Radar Chart Components

// Hilfsfunktionen und -strukturen
struct RadarChartPoint {
    let position: CGPoint
    let value: CGFloat
}

struct RadarChartAxisPoint {
    let center: CGPoint
    let end: CGPoint
    let labelPosition: CGPoint
    let name: String
    let shortName: String // Optimierte Kurzbezeichnung
    let angle: CGFloat // Winkel für Rotation
}

// Hintergrund-Komponente
struct RadarChartBackground: View {
    let values: [CompassValue]
    let maxValue: Int
    let geometry: GeometryProxy
    
    // Berechnete Eigenschaften
    private var center: CGPoint {
        CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    
    private var radius: CGFloat {
        min(geometry.size.width, geometry.size.height) / 2
    }
    
    private var backgroundCircles: [CGFloat] {
        (1...maxValue).map { CGFloat($0) / CGFloat(maxValue) * radius }
    }
    
    private var axisPoints: [RadarChartAxisPoint] {
        (0..<values.count).map { index in
            let angle = 2 * .pi * CGFloat(index) / CGFloat(values.count) - .pi / 2
            let endPoint = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            
            // Anpassung der Labelposition für bessere Lesbarkeit
            var labelOffset: CGFloat = 35
            
            // Horizontale Positionen (3 und 9 Uhr)
            if abs(sin(angle)) < 0.1 { 
                labelOffset = 50 // Erhöhter Abstand für links und rechts
            } 
            // Vertikale Positionen (12 und 6 Uhr)
            else if abs(cos(angle)) < 0.1 { 
                labelOffset = 50 // Erhöhter Abstand für oben und unten
            }
            
            let labelPosition = CGPoint(
                x: center.x + (radius + labelOffset) * cos(angle),
                y: center.y + (radius + labelOffset) * sin(angle)
            )
            
            // Optimierte Kurzbezeichnung erstellen
            let fullName = values[index].name
            let shortName = getOptimizedLabel(for: fullName)
            
            return RadarChartAxisPoint(
                center: center,
                end: endPoint,
                labelPosition: labelPosition,
                name: fullName,
                shortName: shortName,
                angle: angle // Winkel für Rotation speichern
            )
        }
    }
    
    // Funktion zur Optimierung der Beschriftungen
    private func getOptimizedLabel(for value: String) -> String {
        switch value {
        case "Gesundheit und Wohlbefinden":
            return "Gesundheit"
        case "Familie und Beziehungen":
            return "Familie"
        case "Freundschaft und soziale Kontakte":
            return "Freundschaft"
        case "Karriere und berufliche Erfüllung":
            return "Karriere"
        case "Finanzielle Sicherheit":
            return "Finanzen"
        case "Persönliches Wachstum und Lernen":
            return "Wachstum"
        case "Freiheit und Unabhängigkeit":
            return "Freiheit"
        case "Kreativität und Selbstausdruck":
            return "Kreativität"
        case "Spaß und Lebensfreude":
            return "Lebensfreude"
        case "Spiritualität oder Sinnhaftigkeit":
            return "Spiritualität"
        case "Altruismus und soziales Engagement":
            return "Engagement"
        default:
            // Fallback: Erstes Wort oder gekürzt, wenn zu lang
            let firstWord = value.components(separatedBy: " ").first ?? value
            return firstWord.count > 10 ? String(firstWord.prefix(10)) : firstWord
        }
    }
    
    var body: some View {
        ZStack {
            // Hintergrundlinien
            ForEach(backgroundCircles.indices, id: \.self) { index in
                let level = index + 1
                let radius = backgroundCircles[index]
                
                BackgroundCircle(
                    radius: radius,
                    sides: values.count,
                    center: center,
                    isOutermost: level == maxValue
                )
                
                // Skala-Beschriftung (nur für gerade Werte)
                if level % 2 == 0 {
                    Text("\(level)")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                        .position(
                            x: center.x,
                            y: center.y - radius
                        )
                }
            }
            
            // Achsenlinien und Beschriftungen
            ForEach(axisPoints.indices, id: \.self) { index in
                let point = axisPoints[index]
                
                // Achsenlinie
                Path { path in
                    path.move(to: point.center)
                    path.addLine(to: point.end)
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                
                // Optimierte Beschriftung mit Rotation für horizontale Achsen
                ZStack {
                    // Hintergrund für bessere Lesbarkeit
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemBackground).opacity(0.7))
                        .frame(width: 75, height: 16)
                    
                    // Beschriftungstext
                    Text(point.shortName)
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                .frame(width: 75, height: 16)
                // Rotation für horizontale Beschriftungen (3 und 9 Uhr)
                .rotationEffect(isHorizontalAxis(angle: point.angle) ? Angle(degrees: getRotationAngle(angle: point.angle)) : .zero)
                .position(point.labelPosition)
            }
        }
    }
    
    // Hilfsfunktion zur Bestimmung, ob es sich um eine horizontale Achse handelt
    private func isHorizontalAxis(angle: CGFloat) -> Bool {
        // Ungefähr 3 Uhr (0°) oder 9 Uhr (180°)
        return abs(sin(angle)) < 0.3
    }
    
    // Hilfsfunktion zur Bestimmung des Rotationswinkels
    private func getRotationAngle(angle: CGFloat) -> Double {
        // Bei 3 Uhr (0°) rotieren wir um 90°, bei 9 Uhr (180°) um -90°
        if cos(angle) > 0 {
            return 90
        } else {
            return -90
        }
    }
}

struct BackgroundCircle: View {
    let radius: CGFloat
    let sides: Int
    let center: CGPoint
    let isOutermost: Bool
    
    var body: some View {
        createPolygon()
            .stroke(Color.gray.opacity(0.3), lineWidth: isOutermost ? 2 : 1)
    }
    
    private func createPolygon() -> Path {
        var path = Path()
        let angle = 2 * .pi / CGFloat(sides)
        
        for i in 0..<sides {
            let currentAngle = angle * CGFloat(i) - .pi / 2
            let x = center.x + radius * cos(currentAngle)
            let y = center.y + radius * sin(currentAngle)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
}

// Daten-Komponente
struct RadarChartDataLayer: View {
    let values: [CompassValue]
    let maxValue: Int
    let geometry: GeometryProxy
    let isImportance: Bool
    
    // Berechnete Eigenschaften
    private var center: CGPoint {
        CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    
    private var radius: CGFloat {
        min(geometry.size.width, geometry.size.height) / 2
    }
    
    private var dataValues: [CGFloat] {
        values.map { isImportance ? CGFloat($0.importance) / CGFloat(maxValue) : CGFloat($0.satisfaction) / CGFloat(maxValue) }
    }
    
    private var color: Color {
        isImportance ? Color.blue : Color.green
    }
    
    private var dataPoints: [RadarChartPoint] {
        (0..<values.count).map { index in
            let angle = 2 * .pi * CGFloat(index) / CGFloat(values.count) - .pi / 2
            let value = dataValues[index]
            let position = CGPoint(
                x: center.x + radius * value * cos(angle),
                y: center.y + radius * value * sin(angle)
            )
            return RadarChartPoint(position: position, value: value)
        }
    }
    
    var body: some View {
        ZStack {
            // Polygon
            DataPolygon(
                dataValues: dataValues,
                radius: radius,
                center: center,
                color: color
            )
            
            // Datenpunkte
            ForEach(dataPoints.indices, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .position(dataPoints[index].position)
            }
        }
    }
}

struct DataPolygon: View {
    let dataValues: [CGFloat]
    let radius: CGFloat
    let center: CGPoint
    let color: Color
    
    var body: some View {
        createDataPolygon()
            .fill(color.opacity(0.4))
            .overlay(
                createDataPolygon()
                    .stroke(color, lineWidth: 2)
            )
    }
    
    private func createDataPolygon() -> Path {
        var path = Path()
        let angle = 2 * .pi / CGFloat(dataValues.count)
        
        for i in 0..<dataValues.count {
            let currentAngle = angle * CGFloat(i) - .pi / 2
            let adjustedRadius = radius * dataValues[i]
            let x = center.x + adjustedRadius * cos(currentAngle)
            let y = center.y + adjustedRadius * sin(currentAngle)
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
}

// Legende
struct RadarChartLegend: View {
    var body: some View {
        HStack(spacing: 20) {
            // Wichtigkeit
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.blue.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 1)
                    )
                Text("Wichtigkeit")
                    .font(.caption)
            }
            
            // Zufriedenheit
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.green.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Rectangle()
                            .stroke(Color.green, lineWidth: 1)
                    )
                Text("Zufriedenheit")
                    .font(.caption)
            }
        }
        .padding(8)
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(8)
        .shadow(radius: 2)
    }
}

// MARK: - Radar Chart View
struct RadarChartView: View {
    let values: [CompassValue]
    let maxValue: Int = 10
    
    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                ZStack {
                    // Hintergrund und Achsen
                    RadarChartBackground(values: values, maxValue: maxValue, geometry: geometry)
                    
                    // Wichtigkeits-Daten
                    RadarChartDataLayer(values: values, maxValue: maxValue, geometry: geometry, isImportance: true)
                    
                    // Zufriedenheits-Daten
                    RadarChartDataLayer(values: values, maxValue: maxValue, geometry: geometry, isImportance: false)
                }
            }
            .padding(.bottom, 10)
            
            VStack(spacing: 5) {
                RadarChartLegend()
                
                Text("Skala: 1-10")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 5)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
        .frame(height: 350)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(10)
    }
}

struct VisionBoardView: View {
    @ObservedObject var viewModel: VisionBoardViewModel
    @State private var showingExercisePicker = false
    @State private var showingAddValue = false
    @State private var showingAddGoal = false
    @State private var showingEditLifestyle = false
    @State private var showingEditPersonality = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // Progress Overview
                ProgressOverviewCard(progress: viewModel.completionProgress)
                
                // Vision Board Sections
                if let board = viewModel.visionBoard {
                    // Value Compass Section
                    VisionBoardSection(
                        title: "Persönlicher Wertekompass",
                        systemImage: "compass.drawing",
                        color: .purple
                    ) {
                        if board.valueCompass == nil {
                            EmptyStateButton(
                                title: "Erstelle deinen Wertekompass",
                                exercise: .valueCompass
                            ) {
                                viewModel.startExercise(.valueCompass)
                                showingExercisePicker = true
                            }
                        } else if let compass = board.valueCompass {
                            VStack(alignment: .leading, spacing: 15) {
                                // Spinnendiagramm
                                if compass.values.count >= 3 {
                                    RadarChartView(values: compass.values)
                                }
                                
                                // Werte mit größter Differenz
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Werte mit Handlungsbedarf")
                                            .font(.subheadline.bold())
                                    }
                                    
                                    Text("Diese Werte zeigen die größte Differenz zwischen Wichtigkeit und aktueller Zufriedenheit. Hier könntest du ansetzen, um dein Leben mehr in Einklang mit deinen Werten zu bringen.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.bottom, 5)
                                    
                                    let sortedValues = compass.values.sorted(by: { $0.gap > $1.gap })
                                    let valuesToShow = sortedValues.prefix(3).filter { $0.gap > 0 }
                                    
                                    if valuesToShow.isEmpty {
                                        Text("Alle deine Werte sind gut ausbalanciert!")
                                            .font(.subheadline)
                                            .foregroundColor(.green)
                                            .padding()
                                    } else {
                                        ForEach(Array(valuesToShow.enumerated()), id: \.element.id) { index, value in
                                            HStack(alignment: .center, spacing: 15) {
                                                Text("\(index + 1).")
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 25, alignment: .leading)
                                                
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text(value.name)
                                                        .font(.subheadline.bold())
                                                    
                                                    HStack(alignment: .center, spacing: 0) {
                                                        Group {
                                                            Text("Wichtigkeit: ")
                                                                .foregroundColor(.secondary)
                                                            Text("\(value.importance)")
                                                                .foregroundColor(.primary)
                                                                .bold()
                                                        }
                                                        .font(.caption)
                                                        
                                                        Text(" | ")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        
                                                        Group {
                                                            Text("Zufriedenheit: ")
                                                                .foregroundColor(.secondary)
                                                            Text("\(value.satisfaction)")
                                                                .foregroundColor(.primary)
                                                                .bold()
                                                        }
                                                        .font(.caption)
                                                        
                                                        Spacer()
                                                        
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "exclamationmark.triangle.fill")
                                                                .foregroundColor(.orange)
                                                                .font(.caption)
                                                            
                                                            Text("\(value.gap)")
                                                                .font(.caption.bold())
                                                                .foregroundColor(value.gap > 3 ? .red : .orange)
                                                        }
                                                    }
                                                }
                                            }
                                            .padding()
                                            .background(Color(.systemBackground))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(10)
                                
                                Divider()
                                    .padding(.vertical, 5)
                                
                                Text("Dein Wertekompass hilft dir, Entscheidungen zu treffen, die im Einklang mit deinen wichtigsten Werten stehen. Achte besonders auf die Bereiche mit großer Differenz zwischen Wichtigkeit und Zufriedenheit.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                
                                Button(action: {
                                    viewModel.startExercise(.valueCompass)
                                    showingExercisePicker = true
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                        Text("Wertekompass aktualisieren")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    
                    // Goals Section
                    VisionBoardSection(
                        title: "Lebensziele",
                        systemImage: "target",
                        color: .orange
                    ) {
                        if board.goals.isEmpty {
                            EmptyStateButton(
                                title: "Setze deine Ziele",
                                exercise: .goals
                            ) {
                                viewModel.startExercise(.goals)
                                showingExercisePicker = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                ForEach(board.goals) { goal in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(goal.title)
                                                .font(.headline)
                                            Spacer()
                                            Text(goal.category.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(8)
                                        }
                                        if !goal.description.isEmpty {
                                            Text(goal.description)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        if let date = goal.targetDate {
                                            Text("Zieldatum: \(date.formatted(.dateTime.day().month().year()))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    showingAddGoal = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Ziel hinzufügen")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    
                    // Lifestyle Vision Section
                    VisionBoardSection(
                        title: "Traumlebensstil",
                        systemImage: "sun.max.fill",
                        color: .yellow
                    ) {
                        if board.lifestyleVision.isEmpty {
                            EmptyStateButton(
                                title: "Visualisiere deinen Lebensstil",
                                exercise: .lifestyle
                            ) {
                                viewModel.startExercise(.lifestyle)
                                showingExercisePicker = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                if !board.lifestyleVision.dailyRoutine.isEmpty {
                                    VisionSection(title: "Tagesablauf", text: board.lifestyleVision.dailyRoutine)
                                }
                                if !board.lifestyleVision.livingEnvironment.isEmpty {
                                    VisionSection(title: "Wohnumgebung", text: board.lifestyleVision.livingEnvironment)
                                }
                                if !board.lifestyleVision.workLife.isEmpty {
                                    VisionSection(title: "Arbeitsleben", text: board.lifestyleVision.workLife)
                                }
                                if !board.lifestyleVision.relationships.isEmpty {
                                    VisionSection(title: "Beziehungen", text: board.lifestyleVision.relationships)
                                }
                                if !board.lifestyleVision.hobbies.isEmpty {
                                    VisionSection(title: "Hobbys & Freizeit", text: board.lifestyleVision.hobbies)
                                }
                                if !board.lifestyleVision.health.isEmpty {
                                    VisionSection(title: "Gesundheit & Wohlbefinden", text: board.lifestyleVision.health)
                                }
                                
                                Button(action: {
                                    showingEditLifestyle = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil.circle.fill")
                                        Text("Bearbeiten")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    
                    // Desired Personality Section
                    VisionBoardSection(
                        title: "Ideales Selbst",
                        systemImage: "person.fill",
                        color: .blue
                    ) {
                        if board.desiredPersonality.isEmpty {
                            EmptyStateButton(
                                title: "Definiere dein ideales Selbst",
                                exercise: .personality
                            ) {
                                viewModel.startExercise(.personality)
                                showingExercisePicker = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                if !board.desiredPersonality.traits.isEmpty {
                                    VisionSection(title: "Charaktereigenschaften", text: board.desiredPersonality.traits)
                                }
                                if !board.desiredPersonality.mindset.isEmpty {
                                    VisionSection(title: "Denkweise & Einstellung", text: board.desiredPersonality.mindset)
                                }
                                if !board.desiredPersonality.behaviors.isEmpty {
                                    VisionSection(title: "Verhaltensweisen", text: board.desiredPersonality.behaviors)
                                }
                                if !board.desiredPersonality.skills.isEmpty {
                                    VisionSection(title: "Fähigkeiten & Kompetenzen", text: board.desiredPersonality.skills)
                                }
                                if !board.desiredPersonality.habits.isEmpty {
                                    VisionSection(title: "Gewohnheiten", text: board.desiredPersonality.habits)
                                }
                                if !board.desiredPersonality.growth.isEmpty {
                                    VisionSection(title: "Persönliche Entwicklung", text: board.desiredPersonality.growth)
                                }
                                
                                Button(action: {
                                    showingEditPersonality = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil.circle.fill")
                                        Text("Bearbeiten")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                } else {
                    Button(action: {
                        viewModel.createNewVisionBoard()
                    }) {
                        Text("Vision Board erstellen")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(10)
                    }
                    .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Vision Board")
        .sheet(isPresented: $showingExercisePicker) {
            if let exercise = viewModel.currentExercise {
                NavigationView {
                    GuidedExerciseView(viewModel: viewModel, exercise: exercise)
                }
                .onDisappear {
                    // Verzögerung hinzufügen, um sicherzustellen, dass die View aktualisiert wird
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Dummy-Aktualisierung, um die View zu aktualisieren
                        let _ = viewModel.completionProgress
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddValue) {
            AddValueView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddGoal) {
            AddGoalView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingEditLifestyle) {
            EditLifestyleVisionView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingEditPersonality) {
            EditDesiredPersonalityView(viewModel: viewModel)
        }
    }
}

// MARK: - Supporting Views

struct ProgressOverviewCard: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Vision Board Fortschritt")
                .font(.headline)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
            
            Text("\(Int(progress * 100))% Vollständig")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct VisionBoardSection<Content: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    let content: Content
    
    init(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            content
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct EmptyStateButton: View {
    let title: String
    let exercise: VisionBoardViewModel.GuidedExercise
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VisionSection: View {
    let title: String
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(8)
        }
    }
}

#Preview {
    NavigationView {
        VisionBoardView(viewModel: VisionBoardViewModel())
    }
} 