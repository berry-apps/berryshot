import Foundation
import SwiftData

@MainActor
public class HistoryService {
    public static let shared = HistoryService()
    
    public let modelContainer: ModelContainer
    
    private init() {
        do {
            modelContainer = try ModelContainer(for: ScreenshotModel.self)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    public func save(_ screenshot: ScreenshotModel) {
        let context = modelContainer.mainContext
        context.insert(screenshot)
        try? context.save()
    }
    
    public func fetchAll() -> [ScreenshotModel] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ScreenshotModel>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    public func delete(_ screenshot: ScreenshotModel) {
        let context = modelContainer.mainContext
        context.delete(screenshot)
        try? context.save()
    }
}
