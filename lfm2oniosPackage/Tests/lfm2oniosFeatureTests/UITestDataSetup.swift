import Testing
import Foundation
@testable import lfm2oniosFeature

@Test("Setup UI Test Data for Simulator Testing")
func setupUITestData() throws {
    try SimulatorTestDataGenerator.createTestConversationsForUI()
    
    // Verify the conversations were created
    let service = ConversationService()
    let conversations = service.loadAllConversations()
    
    #expect(conversations.count >= 5)
    
    // Verify we have the expected test conversations
    let titles = conversations.map { $0.title }
    #expect(titles.contains("SwiftUI Best Practices"))
    #expect(titles.contains("iOS App Architecture"))
    #expect(titles.contains("Machine Learning on iOS"))
    #expect(titles.contains("Swift Concurrency Guide"))
    #expect(titles.contains("Performance Optimization"))
    
    print("UI test data setup complete. Ready for simulator testing.")
}