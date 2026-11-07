import Combine
import SwiftData

@MainActor
final class StoreLoader: ObservableObject {
    @Published private(set) var container: ModelContainer?
    private let makeContainer: () throws -> ModelContainer

    init(makeContainer: @escaping () throws -> ModelContainer) {
        self.makeContainer = makeContainer
        retry()
    }

    func retry() {
        guard container == nil else { return }
        do {
            container = try makeContainer()
        } catch {
            // Leave the existing store untouched so a later attempt can recover it.
            container = nil
        }
    }
}
