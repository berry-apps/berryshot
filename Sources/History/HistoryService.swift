import Foundation
import SwiftData

@MainActor
public class HistoryService {
    public static let shared = HistoryService()
    
    public let modelContainer: ModelContainer?
    
    private init() {
        do {
            modelContainer = try ModelContainer(for: ScreenshotModel.self)
        } catch {
            print("⚠️ Could not initialize ModelContainer: \(error)")
            modelContainer = nil
        }
    }
    
    public func save(_ screenshot: ScreenshotModel) {
        guard let context = modelContainer?.mainContext else { return }
        context.insert(screenshot)
        try? context.save()
    }
    
    public func fetchAll() -> [ScreenshotModel] {
        guard let context = modelContainer?.mainContext else { return [] }
        let descriptor = FetchDescriptor<ScreenshotModel>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    public func delete(_ screenshot: ScreenshotModel) {
        guard let context = modelContainer?.mainContext else { return }
        context.delete(screenshot)
        try? context.save()
    }
}
