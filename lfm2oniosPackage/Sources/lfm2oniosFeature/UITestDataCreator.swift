import Foundation

/// Creates test data directly within the app's runtime environment for UI testing
@MainActor
struct UITestDataCreator {
    
    /// Creates realistic test conversations that will appear in the app's conversation history
    static func createTestConversations() async {
        let service = ConversationService()
        
        print("🧪 Creating UI test conversations...")
        
        // Clean up any existing test conversations first
        let existingConversations = service.loadAllConversations()
        let testTitles = [
            "SwiftUI Performance Guide",
            "iOS Architecture Best Practices", 
            "Swift Concurrency Fundamentals",
            "Core Data vs SwiftData Comparison",
            "Unit Testing in Swift"
        ]
        
        for conversation in existingConversations {
            if testTitles.contains(conversation.title) {
                try? service.deleteConversation(id: conversation.id)
            }
        }
        
        // Create realistic test conversations
        let testConversations = [
            createConversation(
                title: "SwiftUI Performance Guide",
                exchanges: [
                    ("How can I optimize SwiftUI performance in my app?", 
                     "Here are key SwiftUI performance optimizations:\n\n1. Use LazyVStack/LazyHStack for large lists\n2. Implement Equatable on your models\n3. Avoid expensive computations in body\n4. Use @Observable instead of ObservableObject\n5. Minimize the scope of state changes"),
                    ("What about memory management in SwiftUI?",
                     "SwiftUI handles most memory management automatically, but you should:\n\n• Be careful with strong reference cycles in closures\n• Avoid retaining large objects unnecessarily\n• Use [weak self] in async tasks when needed\n• Profile with Instruments for complex apps"),
                    ("Any tips for handling large datasets?",
                     "For large datasets in SwiftUI:\n\n• Implement pagination or virtual scrolling\n• Use lazy loading patterns\n• Process data on background queues\n• Cache computed values that don't change frequently\n• Consider using @Observable for better performance")
                ],
                modelSlug: "lfm2-350m"
            ),
            
            createConversation(
                title: "iOS Architecture Best Practices",
                exchanges: [
                    ("What's the recommended architecture for iOS apps in 2025?",
                     "For 2025, the recommended approaches are:\n\n1. **MV Pattern** with SwiftUI's native state management for simple apps\n2. **MVVM with @Observable** for complex business logic\n3. **Clean Architecture** for large enterprise applications\n\nThe key is matching complexity to your app's needs."),
                    ("How does the MV pattern work with SwiftUI?",
                     "MV in SwiftUI leverages:\n\n• @State for local view state\n• @Observable models for business logic\n• @Environment for dependency injection\n• Views as lightweight, disposable components\n\nThis eliminates the need for ViewModels in many cases."),
                    ("What about dependency injection in SwiftUI?",
                     "SwiftUI dependency injection best practices:\n\n• Use @Environment for app-wide services\n• Pass dependencies as properties for feature-specific logic\n• SwiftUI's environment system provides clean DI without complex frameworks\n• Keep dependencies minimal and focused")
                ],
                modelSlug: "lfm2-700m"
            ),
            
            createConversation(
                title: "Swift Concurrency Fundamentals",
                exchanges: [
                    ("Explain async/await and actors in Swift",
                     "Swift Concurrency fundamentals:\n\n**async/await:**\n• Provides clean asynchronous code without callbacks\n• Functions marked 'async' can be suspended and resumed\n• Use 'await' to call async functions\n\n**Actors:**\n• Provide thread-safe access to mutable state\n• Only one task can access actor properties at a time\n• @MainActor isolates code to the main thread for UI updates"),
                    ("When should I use structured concurrency?",
                     "Use structured concurrency for:\n\n• Most asynchronous operations with async/await\n• Automatic cancellation and error propagation\n• Preventing common concurrency bugs\n• View-lifetime bound async work with .task{} in SwiftUI\n\nIt provides better safety than manual Task creation."),
                    ("How do I handle cancellation properly?",
                     "Proper cancellation handling:\n\n• Check Task.isCancelled in long-running operations\n• Use try Task.checkCancellation() to throw if cancelled\n• Design async functions to handle CancellationError gracefully\n• SwiftUI's .task modifier handles cancellation automatically\n• Always clean up resources in cancellation scenarios")
                ],
                modelSlug: "lfm2-350m"
            ),
            
            createConversation(
                title: "Core Data vs SwiftData Comparison",
                exchanges: [
                    ("Should I use Core Data or SwiftData for my new app?",
                     "**Choose SwiftData** for new projects in 2025:\n\n✅ Modern, Swift-native API\n✅ Better type safety and compile-time checks\n✅ Automatic CloudKit sync\n✅ Cleaner SwiftUI integration\n✅ @Model macro eliminates boilerplate\n\nCore Data is still powerful but has more complexity and boilerplate."),
                    ("What are SwiftData's main advantages?",
                     "SwiftData advantages:\n\n1. **@Model macro** - eliminates Core Data boilerplate\n2. **Native Swift types** - no more NSManagedObject\n3. **Automatic CloudKit sync** - built-in cloud synchronization\n4. **@Query property wrapper** - seamless SwiftUI integration\n5. **Compile-time safety** - catch relationship errors at build time\n6. **Better optionals handling** - works with Swift's type system")
                ],
                modelSlug: "lfm2-700m"
            ),
            
            createConversation(
                title: "Unit Testing in Swift",
                exchanges: [
                    ("What are the key principles for good unit tests?",
                     "Good unit tests follow these principles:\n\n**AAA Pattern:** Arrange, Act, Assert\n• **Arrange** - Set up test data and conditions\n• **Act** - Execute the code being tested\n• **Assert** - Verify the expected outcome\n\n**Other principles:**\n• Test one thing at a time\n• Independent and isolated tests\n• Descriptive test names\n• Fast execution\n• Test behavior, not implementation"),
                    ("How should I test SwiftUI views?",
                     "SwiftUI testing strategy:\n\n**Separate concerns:**\n• Test @Observable models and business logic separately\n• Use Swift Testing's @Test macro\n• Test state changes and computed properties\n• Use accessibility identifiers for UI testing when needed\n\n**Focus on logic:**\n• Test the underlying data and state management\n• Verify view models respond correctly to user actions\n• Mock dependencies for isolated testing")
                ],
                modelSlug: "lfm2-350m"
            )
        ]
        
        // Save conversations to the app's document directory
        for conversation in testConversations {
            do {
                try service.saveConversation(conversation)
                print("   ✓ Created: '\(conversation.title)' with \(conversation.messages.count) messages")
            } catch {
                print("   ❌ Failed to create: '\(conversation.title)' - \(error)")
            }
        }
        
        print("🎯 UI test data creation complete! Check conversation history.")
    }
    
    private static func createConversation(
        title: String,
        exchanges: [(user: String, assistant: String)],
        modelSlug: String
    ) -> ChatConversation {
        // Create conversation with first user message
        let firstUserMessage = ChatMessageModel(role: .user, content: exchanges[0].user)
        var conversation = ChatConversation(modelSlug: modelSlug, initialMessage: firstUserMessage)
        
        // Add first assistant response
        let firstAssistantMessage = ChatMessageModel(role: .assistant, content: exchanges[0].assistant)
        conversation.addMessage(firstAssistantMessage)
        
        // Add remaining exchanges
        for i in 1..<exchanges.count {
            let userMessage = ChatMessageModel(role: .user, content: exchanges[i].user)
            let assistantMessage = ChatMessageModel(role: .assistant, content: exchanges[i].assistant)
            
            conversation.addMessage(userMessage)
            conversation.addMessage(assistantMessage)
        }
        
        // Set the title and simulate realistic timestamps
        conversation.setTitle(title)
        
        return conversation
    }
}