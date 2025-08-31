import Foundation
@testable import lfm2oniosFeature

/// Utility to generate test conversations for manual UI testing on simulator
struct SimulatorTestDataGenerator {
    
    static func createTestConversationsForUI() throws {
        let service = ConversationService()
        
        let testConversations = [
            createTestConversation(
                title: "SwiftUI Best Practices",
                messages: [
                    ("user", "What are the best practices for SwiftUI development?"),
                    ("assistant", "SwiftUI best practices include using proper state management with @State and @Observable, keeping views small and focused, leveraging view modifiers effectively, and following the single source of truth principle for data flow."),
                    ("user", "How should I handle navigation in SwiftUI?"),
                    ("assistant", "For navigation, use NavigationStack for simple hierarchical navigation, NavigationSplitView for multi-column layouts on larger screens, and consider using a router pattern for complex navigation flows.")
                ],
                modelSlug: "lfm2-350m"
            ),
            
            createTestConversation(
                title: "iOS App Architecture",
                messages: [
                    ("user", "What's the best architecture pattern for iOS apps in 2025?"),
                    ("assistant", "In 2025, the recommended approaches include MV (Model-View) with SwiftUI's native state management, MVVM with @Observable for complex business logic, or Clean Architecture with well-defined boundaries between layers. The choice depends on your app's complexity and team preferences."),
                    ("user", "How does SwiftUI's @Observable compare to the old ObservableObject?"),
                    ("assistant", "@Observable is more efficient as it only updates views when actually accessed properties change, unlike ObservableObject which required manual @Published annotations. It also provides better performance and cleaner syntax.")
                ],
                modelSlug: "lfm2-700m"
            ),
            
            createTestConversation(
                title: "Machine Learning on iOS",
                messages: [
                    ("user", "How can I integrate machine learning models into my iOS app?"),
                    ("assistant", "You can integrate ML models using Core ML for on-device inference, Create ML for training custom models, or use frameworks like TensorFlow Lite. Core ML provides the best performance and privacy for most use cases."),
                    ("user", "What about large language models like the one we're using now?"),
                    ("assistant", "Large language models can be integrated using frameworks like Llama.cpp for local inference, cloud APIs for powerful models, or hybrid approaches. Consider model size, latency requirements, and privacy needs when choosing your approach.")
                ],
                modelSlug: "lfm2-1.2b"
            ),
            
            createTestConversation(
                title: "Swift Concurrency Guide",
                messages: [
                    ("user", "Explain async/await in Swift"),
                    ("assistant", "Swift's async/await provides a clean way to handle asynchronous operations. Functions marked with 'async' can be suspended and resumed, while 'await' is used to call async functions. This eliminates callback hell and makes asynchronous code more readable."),
                    ("user", "What about actors and @MainActor?"),
                    ("assistant", "Actors provide thread-safe access to mutable state by ensuring only one task can access their properties at a time. @MainActor isolates code to run on the main thread, which is essential for UI updates in SwiftUI applications.")
                ],
                modelSlug: "lfm2-350m"
            ),
            
            createTestConversation(
                title: "Performance Optimization",
                messages: [
                    ("user", "How do I optimize SwiftUI performance?"),
                    ("assistant", "Key optimization strategies include: using LazyVStack/LazyHStack for large lists, implementing proper Equatable conformance on models, avoiding expensive computations in body, using @Observable instead of ObservableObject, and leveraging view identity with .id() sparingly."),
                    ("user", "What about memory management?"),
                    ("assistant", "SwiftUI handles most memory management automatically, but be careful with strong reference cycles in closures (use [weak self]), avoid retaining large objects unnecessarily, and use instruments to profile memory usage in complex apps.")
                ],
                modelSlug: "lfm2-700m"
            )
        ]
        
        // Clean up any existing test conversations first
        let existingConversations = service.loadAllConversations()
        for conversation in existingConversations {
            if conversation.title.contains("SwiftUI") || 
               conversation.title.contains("iOS") || 
               conversation.title.contains("Machine Learning") ||
               conversation.title.contains("Swift Concurrency") ||
               conversation.title.contains("Performance") {
                try? service.deleteConversation(id: conversation.id)
            }
        }
        
        // Save new test conversations
        for conversation in testConversations {
            try service.saveConversation(conversation)
        }
        
        print("Created \(testConversations.count) test conversations for UI testing")
    }
    
    private static func createTestConversation(
        title: String,
        messages: [(String, String)],
        modelSlug: String
    ) -> ChatConversation {
        // Create conversation with first message
        let firstMessage = ChatMessageModel(role: .user, content: messages[0].1)
        var conversation = ChatConversation(modelSlug: modelSlug, initialMessage: firstMessage)
        
        // Add remaining messages
        for i in 1..<messages.count {
            let (roleStr, content) = messages[i]
            let role: MessageRole = roleStr == "user" ? .user : .assistant
            let message = ChatMessageModel(role: role, content: content)
            conversation.addMessage(message)
        }
        
        conversation.setTitle(title)
        return conversation
    }
}