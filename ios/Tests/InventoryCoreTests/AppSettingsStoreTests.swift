import XCTest
@testable import InventoryCore

final class AppSettingsStoreTests: XCTestCase {
    @MainActor
    func testUpdatePersistsSettingsAndMirrorsAppearanceDefaults() {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        var updated = AppSettings.default
        updated.preferredColorScheme = 2
        updated.motionLevel = .off
        updated.enableAnimations = false
        updated.hapticsEnabled = false
        updated.showHealthCardOnHome = false

        store.update(updated)

        XCTAssertEqual(store.settings.preferredColorScheme, 2)
        XCTAssertEqual(store.lastPersistedSettings.preferredColorScheme, 2)
        XCTAssertEqual(defaults.integer(forKey: "preferredColorScheme"), 2)
        XCTAssertEqual(defaults.string(forKey: "motionLevel"), AppSettings.MotionLevel.off.rawValue)
        XCTAssertEqual(defaults.bool(forKey: "enableAnimations"), false)
        XCTAssertEqual(defaults.bool(forKey: "hapticsEnabled"), false)
        XCTAssertEqual(defaults.bool(forKey: "showHealthCardOnHome"), false)
    }

    @MainActor
    func testPublishDraftAndRollbackRestoresLastPersistedSettings() {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)

        var persisted = AppSettings.default
        persisted.preferredColorScheme = 2
        persisted.motionLevel = .reduced
        persisted.enableAnimations = true
        store.update(persisted)

        var draft = persisted
        draft.preferredColorScheme = 1
        draft.motionLevel = .off
        draft.enableAnimations = false
        store.publishDraft(draft)

        XCTAssertEqual(store.settings.preferredColorScheme, 1)
        XCTAssertEqual(store.lastPersistedSettings.preferredColorScheme, 2)
        XCTAssertEqual(defaults.integer(forKey: "preferredColorScheme"), 1)
        XCTAssertEqual(defaults.string(forKey: "motionLevel"), AppSettings.MotionLevel.off.rawValue)

        store.rollbackToLastPersisted()

        XCTAssertEqual(store.settings.preferredColorScheme, 2)
        XCTAssertEqual(store.settings.motionLevel, .reduced)
        XCTAssertEqual(defaults.integer(forKey: "preferredColorScheme"), 2)
        XCTAssertEqual(defaults.string(forKey: "motionLevel"), AppSettings.MotionLevel.reduced.rawValue)
    }
}
