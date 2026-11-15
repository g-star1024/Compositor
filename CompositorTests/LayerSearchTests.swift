import AppKit
import Testing
@testable import Compositor

/// The Layers panel's name search and type filter narrow the same rows the list draws, and clear back to all.
@MainActor struct LayerSearchTests {
    @Test func nameSearchAndTypeFilterNarrowTheRows() throws {
        let session = EditorSession()
        session.createDocument(width: 120, height: 80)
        session.addBlankLayer()
        session.addBlankLayer()
        #expect(session.document?.layers.count == 2)
        session.document?.layers[0].name = "Sky"
        session.document?.layers[1].name = "Ground"

        #expect(session.filteredLayerRows.count == 2)
        #expect(!session.isFilteringLayers)

        session.layerSearchText = "sky"
        #expect(session.isFilteringLayers)
        #expect(session.filteredLayerRows.map(\.layer.name) == ["Sky"])

        session.layerSearchText = "nothing matches"
        #expect(session.filteredLayerRows.isEmpty)

        session.clearLayerSearch()
        #expect(session.filteredLayerRows.count == 2)

        session.layerTypeFilter = [.folder]
        #expect(session.isFilteringLayers)
        #expect(session.filteredLayerRows.isEmpty)
        session.clearLayerTypeFilter()
        #expect(!session.isFilteringLayers)
        #expect(session.filteredLayerRows.count == 2)
    }
}
