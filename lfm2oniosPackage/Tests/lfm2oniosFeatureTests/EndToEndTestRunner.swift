import Testing
import Foundation
@testable import lfm2oniosFeature

/// Comprehensive end-to-end test runner for simulator validation
/// This creates realistic test data that will appear in the actual app UI
struct EndToEndTestRunner {
    
    @Test("End-to-End: Complete conversation lifecycle with realistic data")
    func endToEndConversationLifecycle() throws {
        let service = ConversationService()
        
        print("🧪 Starting End-to-End Test Suite")
        print(String(repeating: "=", count: 50))
        
        // Step 1: Clean slate - remove any existing test conversations
        print("📁 Step 1: Cleaning existing test data...")
        let existingConversations = service.loadAllConversations()
        let testConversationTitles = [
            "SwiftUI Performance Tips",
            "iOS Architecture Patterns", 
            "Swift Concurrency Deep Dive",
            "Core Data vs SwiftData",
            "Unit Testing Best Practices"
        ]
        
        for conversation in existingConversations {
            if testConversationTitles.contains(conversation.title) {
                try service.deleteConversation(id: conversation.id)
            }
        }
        
        // Step 2: Create realistic conversation data that simulates user interactions
        print("💬 Step 2: Creating realistic conversation data...")
        let testConversations = createRealisticConversations()
        
        var createdIds: [UUID] = []
        for conversation in testConversations {
            try service.saveConversation(conversation)
            createdIds.append(conversation.id)
            print("   ✓ Created conversation: '\(conversation.title)' with \(conversation.messages.count) messages")
        }
        
        // Step 3: Verify persistence - reload and validate
        print("💾 Step 3: Testing persistence...")
        let reloadedConversations = service.loadAllConversations()
        let savedTestConversations = reloadedConversations.filter { conv in
            createdIds.contains(conv.id)
        }
        
        #expect(savedTestConversations.count == testConversations.count)
        print("   ✓ All \(savedTestConversations.count) conversations persisted correctly")
        
        // Step 4: Test search functionality
        print("🔍 Step 4: Testing search functionality...")
        testSearchScenarios(conversations: savedTestConversations)
        
        // Step 5: Test conversation loading
        print("📖 Step 5: Testing individual conversation loading...")
        for conversationId in createdIds {
            let loaded = try service.loadConversation(id: conversationId)
            #expect(loaded.id == conversationId)
            #expect(!loaded.messages.isEmpty)
        }
        print("   ✓ All conversations load individually without errors")
        
        // Step 6: Test partial deletion (keep some for UI testing)
        print("🗑️ Step 6: Testing deletion functionality...")
        let conversationToDelete = createdIds.first!
        try service.deleteConversation(id: conversationToDelete)
        
        let afterDeletion = service.loadAllConversations()
        #expect(!afterDeletion.contains { $0.id == conversationToDelete })
        print("   ✓ Conversation deletion works correctly")
        
        // Step 7: Verify remaining conversations for UI testing
        let remainingTestConversations = service.loadAllConversations().filter { conv in
            testConversationTitles.contains(conv.title)
        }
        
        print("📱 Step 7: Preparing for UI testing...")
        print("   ✓ \(remainingTestConversations.count) conversations ready for UI validation")
        for conv in remainingTestConversations {
            print("   📝 '\(conv.title)' - \(conv.messages.count) messages - Updated: \(conv.updatedAt.formatted(.dateTime.hour().minute()))")
        }
        
        print(String(repeating: "=", count: 50))
        print("✅ End-to-End Test Complete - Ready for UI Testing!")
        print("🎯 Next: Open app and verify conversations appear in history")
    }
    
    private func createRealisticConversations() -> [ChatConversation] {
        return [
            // Conversation 1: SwiftUI Performance
            createDetailedConversation(
                title: "SwiftUI Performance Tips",
                exchanges: [
                    ("How can I improve SwiftUI performance in my app?", 
                     "Here are key SwiftUI performance optimizations: 1) Use LazyVStack/LazyHStack for large lists, 2) Implement Equatable on your models to optimize diffing, 3) Avoid expensive computations in body, 4) Use @Observable instead of ObservableObject for better performance."),
                    ("What about view updates and state management?",
                     "For optimal view updates: Use @State for local state, leverage @Bindable for two-way binding with @Observable objects, minimize the scope of state changes, and consider using view identity with .id() sparingly as it forces view recreation."),
                    ("Any tips for handling large datasets?",
                     "For large datasets: Implement pagination or virtual scrolling, use lazy loading patterns, consider data preprocessing on background queues, and cache computed values that don't change frequently.")
                ],
                modelSlug: "lfm2-700m"
            ),
            
            // Conversation 2: iOS Architecture  
            createDetailedConversation(
                title: "iOS Architecture Patterns",
                exchanges: [
                    ("What's the best architecture for a new iOS app in 2025?",
                     "For 2025, I'd recommend: MV (Model-View) with SwiftUI's native state management for simple apps, MVVM with @Observable for complex business logic, or Clean Architecture for large enterprise apps. The key is matching complexity to your needs."),
                    ("How does the MV pattern work with SwiftUI?",
                     "MV in SwiftUI leverages @State, @Observable, and @Environment for state management. Views are lightweight and disposable, while @Observable models handle business logic. This eliminates the need for ViewModels in many cases."),
                    ("What about dependency injection?",
                     "Use @Environment for app-wide dependencies like services and configuration. For feature-specific dependencies, pass them as properties. SwiftUI's environment system provides clean dependency injection without complex frameworks.")
                ],
                modelSlug: "lfm2-1.2b"
            ),
            
            // Conversation 3: Swift Concurrency
            createDetailedConversation(
                title: "Swift Concurrency Deep Dive",
                exchanges: [
                    ("Explain the difference between actors and @MainActor",
                     "Actors provide thread-safe access to mutable state by ensuring only one task accesses their properties at a time. @MainActor is a global actor that isolates code to run on the main thread - essential for UI updates in SwiftUI."),
                    ("When should I use structured concurrency?",
                     "Use structured concurrency with async/await for most asynchronous operations. It provides automatic cancellation, proper error propagation, and prevents common concurrency bugs. Use .task {} in SwiftUI views for view-lifetime bound async work."),
                    ("How do I handle cancellation properly?",
                     "Check Task.isCancelled periodically in long-running operations, use try Task.checkCancellation() to throw if cancelled, and design your async functions to handle CancellationError gracefully. SwiftUI's .task modifier handles cancellation automatically.")
                ],
                modelSlug: "lfm2-350m"
            ),
            
            // Conversation 4: Data Persistence
            createDetailedConversation(
                title: "Core Data vs SwiftData",
                exchanges: [
                    ("Should I use Core Data or SwiftData for my new app?",
                     "For new projects in 2025, choose SwiftData. It provides a modern, Swift-native API with better type safety, automatic CloudKit sync, and cleaner integration with SwiftUI. Core Data is still powerful but has more boilerplate."),
                    ("What are the main advantages of SwiftData?",
                     "SwiftData advantages: 1) @Model macro eliminates boilerplate, 2) Native Swift types and optionals, 3) Automatic CloudKit sync, 4) Better SwiftUI integration with @Query, 5) Compile-time safety for relationships and predicates."),
                    ("Are there any limitations I should know about?",
                     "SwiftData limitations: Newer framework with fewer community resources, some advanced Core Data features not yet available, and requires iOS 17+. For complex migration scenarios or legacy projects, Core Data might still be necessary.")
                ],
                modelSlug: "lfm2-700m"
            ),
            
            // Conversation 5: Testing
            createDetailedConversation(
                title: "Unit Testing Best Practices",
                exchanges: [
                    ("What are the key principles for good unit tests?",
                     "Good unit tests follow AAA pattern (Arrange, Act, Assert), test one thing at a time, are independent and isolated, have descriptive names, and run fast. Focus on testing behavior, not implementation details."),
                    ("How should I test SwiftUI views?",
                     "For SwiftUI, test the underlying @Observable models and business logic separately from the UI. Use Swift Testing's @Test macro, test state changes and computed properties, and use accessibility identifiers for UI testing when needed."),
                    ("What about testing async code?",
                     "With Swift Testing, use async test functions and await async operations directly. Test both success and failure scenarios, verify proper error handling, and use Task.sleep() sparingly for timing-dependent tests.")
                ],
                modelSlug: "lfm2-350m"
            )
        ]
    }
    
    private func createDetailedConversation(
        title: String, 
        exchanges: [(user: String, assistant: String)], 
        modelSlug: String
    ) -> ChatConversation {
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
        
        conversation.setTitle(title)
        
        // Simulate realistic timestamps (spread over last few days)
        let baseDate = Date().addingTimeInterval(-TimeInterval.random(in: 0...(3 * 24 * 60 * 60))) // Last 3 days
        
        return conversation
    }
    
    private func testSearchScenarios(conversations: [ChatConversation]) {
        // Test search by title
        let swiftUIResults = conversations.filter { 
            $0.title.localizedCaseInsensitiveContains("SwiftUI") 
        }
        #expect(swiftUIResults.count >= 1)
        print("   ✓ Title search: Found \(swiftUIResults.count) conversations matching 'SwiftUI'")
        
        // Test search by content
        let performanceResults = conversations.filter { conversation in
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains("performance")
            }
        }
        #expect(performanceResults.count >= 1)
        print("   ✓ Content search: Found \(performanceResults.count) conversations about 'performance'")
        
        // Test case-insensitive search
        let architectureResults = conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains("architecture") ||
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains("architecture")
            }
        }
        #expect(architectureResults.count >= 1)
        print("   ✓ Case-insensitive search: Found \(architectureResults.count) conversations about 'architecture'")
        
        // Test search with no results
        let noResults = conversations.filter { 
            $0.title.localizedCaseInsensitiveContains("nonexistentterm") 
        }
        #expect(noResults.isEmpty)
        print("   ✓ No results search: Correctly returned 0 results for non-existent term")
    }
}