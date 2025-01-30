import SwiftUI

struct JournalEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: JournalViewModel
    
    @State private var gratitude: String
    @State private var highlight: String
    @State private var learning: String
    @State private var showingAISuggestions = false
    @State private var showingLearningNugget = false
    @State private var selectedField: JournalField?
    @State private var showingDeleteConfirmation = false
    
    private let entry: JournalEntry?
    private let isEditing: Bool
    
    enum JournalField: String {
        case gratitude = "Gratitude"
        case highlight = "Highlight"
        case learning = "Learning"
    }
    
    init(viewModel: JournalViewModel, entry: JournalEntry? = nil) {
        self.viewModel = viewModel
        self.entry = entry
        self.isEditing = entry != nil
        
        _gratitude = State(initialValue: entry?.gratitude ?? "")
        _highlight = State(initialValue: entry?.highlight ?? "")
        _learning = State(initialValue: entry?.learning ?? "")
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Date Header
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.purple)
                    Text(entry?.date ?? Date(), style: .date)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                
                // Gratitude Section
                JournalSection(
                    title: "What are you grateful for today?",
                    text: $gratitude,
                    systemImage: "heart.fill",
                    color: .red
                ) {
                    selectedField = .gratitude
                    showingAISuggestions = true
                }
                
                // Highlight Section
                JournalSection(
                    title: "What was your highlight today?",
                    text: $highlight,
                    systemImage: "star.fill",
                    color: .yellow
                ) {
                    selectedField = .highlight
                    showingAISuggestions = true
                }
                
                // Learning Section
                JournalSection(
                    title: "What did you learn today?",
                    text: $learning,
                    systemImage: "book.fill",
                    color: .blue
                ) {
                    selectedField = .learning
                    showingAISuggestions = true
                }
                
                // Learning Nugget
                if let nugget = entry?.learningNugget {
                    LearningNuggetView(nugget: nugget)
                } else {
                    Button(action: {
                        showingLearningNugget = true
                    }) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text("Get Daily Learning Nugget")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
        .navigationBarItems(
            leading: Button("Cancel") {
                dismiss()
            },
            trailing: HStack {
                if isEditing {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                
                Button("Save") {
                    saveEntry()
                }
                .disabled(gratitude.isEmpty && highlight.isEmpty && learning.isEmpty)
            }
        )
        .sheet(isPresented: $showingAISuggestions) {
            AISuggestionsView(
                field: selectedField ?? .gratitude,
                suggestions: viewModel.aiSuggestions
            ) { suggestion in
                switch selectedField {
                case .gratitude:
                    gratitude = suggestion
                case .highlight:
                    highlight = suggestion
                case .learning:
                    learning = suggestion
                case .none:
                    break
                }
            }
        }
        .sheet(isPresented: $showingLearningNugget) {
            LearningNuggetPickerView(viewModel: viewModel)
        }
        .alert("Delete Entry", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let entry = entry {
                    viewModel.deleteEntry(entry)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this entry? This action cannot be undone.")
        }
    }
    
    private func saveEntry() {
        let updatedEntry = JournalEntry(
            id: entry?.id ?? UUID().uuidString,
            userId: entry?.userId ?? "",
            date: entry?.date ?? Date(),
            gratitude: gratitude,
            highlight: highlight,
            learning: learning,
            learningNugget: entry?.learningNugget,
            lastModified: Date(),
            syncStatus: .pendingUpload
        )
        
        viewModel.saveEntry(updatedEntry)
        dismiss()
    }
}

// MARK: - Supporting Views

struct JournalSection: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    let color: Color
    let onSuggestionTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: onSuggestionTap) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.purple)
                }
            }
            
            TextEditor(text: $text)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2))
                )
        }
    }
}

struct LearningNuggetView: View {
    let nugget: LearningNugget
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Daily Learning Nugget")
                    .font(.headline)
                Spacer()
                Text(nugget.category.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
            
            Text(nugget.content)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
        }
    }
}

struct AISuggestionsView: View {
    @Environment(\.dismiss) private var dismiss
    let field: JournalEntryView.JournalField
    let suggestions: [String]
    let onSelect: (String) -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        onSelect(suggestion)
                        dismiss()
                    }) {
                        Text(suggestion)
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("Suggestions for \(field.rawValue)")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
}

struct LearningNuggetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: JournalViewModel
    
    var body: some View {
        NavigationView {
            List(LearningNugget.Category.allCases, id: \.self) { category in
                Button(action: {
                    viewModel.generateLearningNugget(for: category)
                    viewModel.addLearningNuggetToEntry()
                    dismiss()
                }) {
                    HStack {
                        Text(category.rawValue.capitalized)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Choose Category")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
}

#Preview {
    NavigationView {
        JournalEntryView(viewModel: JournalViewModel())
    }
} 