import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    let gradient: Gradient
    let content: () -> Content
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    
    init(
        title: String,
        systemImage: String,
        gradient: Gradient = Gradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)]),
        @ViewBuilder content: @escaping () -> Content,
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.gradient = gradient
        self.content = content
        self.onTap = onTap
        self.onLongPress = onLongPress
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                gradient: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(0.1)
                )
                .shadow(radius: 5, x: 0, y: 2)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onTap?()
            }
        }
        .onLongPressGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onLongPress?()
            }
        }
    }
}

struct DashboardCard_Previews: PreviewProvider {
    static var previews: some View {
        DashboardCard(
            title: "Test Card",
            systemImage: "star.fill"
        ) {
            Text("Card Content")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
} 