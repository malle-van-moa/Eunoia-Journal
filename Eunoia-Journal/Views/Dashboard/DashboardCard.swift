import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    let gradient: Gradient
    let content: Content
    
    init(
        title: String,
        systemImage: String,
        gradient: Gradient,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.gradient = gradient
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

#Preview {
    DashboardCard(
        title: "Test Card",
        systemImage: "star.fill",
        gradient: Gradient(colors: [.blue.opacity(0.4), .cyan.opacity(0.4)])
    ) {
        Text("Test Content")
            .foregroundColor(.secondary)
    }
    .padding()
} 