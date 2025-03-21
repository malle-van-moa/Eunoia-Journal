import SwiftUI
import Combine
import FirebaseAuth
import CoreData

@available(iOS 17.0, *)
class DashboardViewModel: ObservableObject {
    @Published var greeting: String = ""
    @Published var motivationalMessage: String = ""
    @Published var currentMood: Mood?
    @Published var streakCount: Int = 0
    @Published var dailyChallenge: Challenge?
    @Published var lastJournalEntries: [JournalEntry] = []
    @Published var journaledDaysThisWeek: Set<Int> = []
    @Published var isStreakAnimating: Bool = false
    @Published var showingMissedDayAlert: Bool = false
    @Published var lastStreakCount: Int = 0
    @Published var streakStartDate: Date? = nil
    
    private var cancellables = Set<AnyCancellable>()
    private let calendar = Calendar.current
    
    var currentWeekday: Int {
        // Convert Sunday = 1 to Monday = 1
        let weekday = calendar.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }
    
    // Gibt den ersten Wochentag zurück, basierend auf dem Streak-Startdatum
    // Wenn kein Streak-Startdatum vorhanden ist, wird Montag (1) zurückgegeben
    var firstDisplayedWeekday: Int {
        guard let startDate = streakStartDate else { return 1 }
        let weekday = calendar.component(.weekday, from: startDate)
        // Konvertiere von Sonntag = 1 zu Montag = 1 Format
        return weekday == 1 ? 7 : weekday - 1
    }
    
    init() {
        updateGreeting()
        fetchDailyChallenge()
        fetchStreakCount()
        fetchLastJournalEntries()
        updateJournaledDays()
        
        // Update greeting every minute to handle time changes
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateGreeting()
            }
            .store(in: &cancellables)
            
        // Auf Streak-Updates reagieren
        NotificationCenter.default.publisher(for: NSNotification.Name("StreakUpdated"))
            .sink { [weak self] notification in
                if let streakCount = notification.userInfo?["streakCount"] as? Int {
                    DispatchQueue.main.async {
                        self?.updateStreakCount(streakCount)
                    }
                }
                
                if let startDate = notification.userInfo?["streakStartDate"] as? Date {
                    DispatchQueue.main.async {
                        self?.streakStartDate = startDate
                        self?.updateJournaledDays()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateJournaledDays() {
        // Get the start of the current week (Monday)
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return }
        
        // Create date range for the week
        let weekDates = (0...6).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
        
        // Filter journal entries for this week
        journaledDaysThisWeek = Set(lastJournalEntries
            .filter { entry in
                weekDates.contains { calendar.isDate($0, inSameDayAs: entry.date) }
            }
            .compactMap { entry in
                let weekday = calendar.component(.weekday, from: entry.date)
                return weekday == 1 ? 7 : weekday - 1 // Convert to Monday = 1 format
            })
    }
    
    func checkMissedDay(_ day: Int) {
        guard !journaledDaysThisWeek.contains(day) else { return }
        
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())),
              let targetDate = calendar.date(byAdding: .day, value: day - 1, to: startOfWeek),
              targetDate < Date() else { return }
        
        showingMissedDayAlert = true
    }
    
    func updateStreakCount(_ newCount: Int) {
        if newCount != streakCount {
            lastStreakCount = streakCount
            streakCount = newCount
            isStreakAnimating = true
            
            // Reset animation flag after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.isStreakAnimating = false
            }
        }
    }
    
    func updateGreeting() {
        let hour = calendar.component(.hour, from: Date())
        let name = UserDefaults.standard.string(for: .userName) ?? ""
        
        greeting = switch hour {
            case 5..<12: "Guten Morgen\(name.isEmpty ? "" : ", \(name)")!"
            case 12..<17: "Guten Tag\(name.isEmpty ? "" : ", \(name)")!"
            case 17..<22: "Guten Abend\(name.isEmpty ? "" : ", \(name)")!"
            default: "Gute Nacht\(name.isEmpty ? "" : ", \(name)")!"
        }
        
        updateMotivationalMessage(for: hour)
    }
    
    private func updateMotivationalMessage(for hour: Int) {
        let morningMessages = [
            "Ein neuer Tag voller Möglichkeiten liegt vor dir!",
            "Starte deinen Tag mit Klarheit und Fokus.",
            "Jeder Morgen ist ein neuer Anfang."
        ]
        
        let dayMessages = [
            "Bleib fokussiert auf deine Ziele!",
            "Jeder Schritt bringt dich näher an deine Vision.",
            "Du bist auf dem richtigen Weg!"
        ]
        
        let eveningMessages = [
            "Zeit, über den Tag zu reflektieren.",
            "Was hat dich heute glücklich gemacht?",
            "Welche Erkenntnisse nimmst du mit?"
        ]
        
        let nightMessages = [
            "Ein perfekter Moment für tiefe Reflexion.",
            "Lass den Tag Revue passieren.",
            "Morgen ist ein neuer Tag voller Möglichkeiten."
        ]
        
        let messages = switch hour {
            case 5..<12: morningMessages
            case 12..<17: dayMessages
            case 17..<22: eveningMessages
            default: nightMessages
        }
        
        motivationalMessage = messages.randomElement() ?? messages[0]
    }
    
    private func fetchDailyChallenge() {
        // TODO: Implement challenge fetching logic
        dailyChallenge = Challenge(
            title: "Tages-Challenge",
            description: "Schreibe 3 Dinge auf, für die du dankbar bist.",
            type: .gratitude
        )
    }
    
    private func fetchStreakCount() {
        // TODO: Implement streak counting logic
        streakCount = UserDefaults.standard.integer(forKey: "journalStreak")
        
        // Streak-Startdatum laden, falls vorhanden
        if let startDate = UserDefaults.standard.object(forKey: "journalStreakStartDate") as? Date {
            streakStartDate = startDate
        }
    }
    
    private func fetchLastJournalEntries() {
        // JournalEntries aus dem Service laden
        guard let userId = FirebaseAuth.Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                // Zuerst versuchen wir, lokale Einträge zu laden
                let entries = try await CoreDataManager.shared.fetchJournalEntries(for: userId)
                
                DispatchQueue.main.async {
                    self.lastJournalEntries = entries.sorted(by: { $0.date > $1.date })
                    self.updateJournaledDays()
                    
                    // Berechne und aktualisiere auch den Streak
                    let journalViewModel = JournalViewModel()
                    let streakInfo = journalViewModel.calculateCurrentStreakWithStartDate()
                    self.updateStreakCount(streakInfo.streak)
                    
                    // Streak-Startdatum aktualisieren
                    self.streakStartDate = streakInfo.startDate
                    
                    // Daten in UserDefaults speichern
                    UserDefaults.standard.set(streakInfo.streak, forKey: "journalStreak")
                    if let startDate = streakInfo.startDate {
                        UserDefaults.standard.set(startDate, forKey: "journalStreakStartDate")
                    }
                }
            } catch {
                print("⚠️ Fehler beim Laden der Journal-Einträge: \(error.localizedDescription)")
            }
        }
    }
    
    func updateMood(_ mood: Mood) {
        currentMood = mood
        // TODO: Save mood to persistent storage
    }
}

// MARK: - Supporting Types

enum Mood: String, CaseIterable {
    case amazing = "🤩"      // Fantastisch
    case happy = "😊"        // Glücklich
    case good = "🙂"         // Gut
    case calm = "😌"         // Entspannt
    case neutral = "😐"      // Neutral
    case tired = "😴"        // Müde
    case stressed = "😓"     // Gestresst
    case sad = "😢"         // Traurig
    case angry = "😠"       // Wütend
    case sick = "🤒"        // Krank
    
    var description: String {
        switch self {
            case .amazing: return "Fantastisch"
            case .happy: return "Glücklich"
            case .good: return "Gut"
            case .calm: return "Entspannt"
            case .neutral: return "Neutral"
            case .tired: return "Müde"
            case .stressed: return "Gestresst"
            case .sad: return "Traurig"
            case .angry: return "Wütend"
            case .sick: return "Krank"
        }
    }
}

struct Challenge {
    let title: String
    let description: String
    let type: ChallengeType
    var isCompleted: Bool = false
}

enum ChallengeType {
    case gratitude
    case reflection
    case vision
    case mindfulness
}

// MARK: - UserDefaults Extension
extension UserDefaults {
    enum Key: String {
        case userName = "user_name"
    }
    
    func string(for key: Key) -> String? {
        string(forKey: key.rawValue)
    }
    
    func set(_ value: String, for key: Key) {
        set(value, forKey: key.rawValue)
    }
} 