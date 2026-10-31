import Testing
@testable import LingoScan

/// T-34: el reparto de páginas es puro; ninguna fila se corta y nada se pierde.
struct MedicalReportPaginatorTests {
    private let content = 600.0
    private let spacing = 10.0

    private func table(_ id: String, rows: Int, rowHeight: Double = 20, title: Double = 30, header: Double = 20,
                       startsPage: Bool = false) -> MedicalFlowItem {
        .table(id: id, titleHeight: title, continuationTitleHeight: 16, headerHeight: header,
               rowHeights: [Double](repeating: rowHeight, count: rows), startsPage: startsPage)
    }

    private func rows(of id: String, in pages: [[MedicalPageSlice]]) -> [Range<Int>] {
        pages.flatMap { $0 }.compactMap { slice in
            guard slice.id == id, case .rows(let range, _) = slice.kind else { return nil }
            return range
        }
    }

    @Test func longTableSplitsAcrossPagesWithoutLosingRows() {
        let pages = MedicalReportPaginator.paginate([table("meals", rows: 120)], contentHeight: content, spacing: spacing)
        #expect(pages.count > 1)
        let ranges = rows(of: "meals", in: pages)
        // Las filas de los tramos son una partición contigua de 0..<120.
        #expect(ranges.first?.lowerBound == 0 && ranges.last?.upperBound == 120)
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
        #expect(ranges.reduce(0) { $0 + $1.count } == 120)
        // Ningún tramo se pasa de la página, y solo el primero no es continuación.
        for page in pages {
            let used = page.reduce(0) { $0 + $1.height } + spacing * Double(page.count - 1)
            #expect(used <= content + 0.001)
        }
        let slices = pages.flatMap { $0 }
        for (index, slice) in slices.enumerated() {
            guard case .rows(_, let isContinuation) = slice.kind else { continue }
            #expect(isContinuation == (index > 0))
        }
    }

    @Test func sliceHeightIsTitlePlusHeaderPlusItsRows() {
        let pages = MedicalReportPaginator.paginate([table("t", rows: 50)], contentHeight: content, spacing: spacing)
        let slices = pages.flatMap { $0 }
        for slice in slices {
            guard case .rows(let range, let isContinuation) = slice.kind else { continue }
            let title = isContinuation ? 16.0 : 30.0
            #expect(slice.height == title + 20 + Double(range.count) * 20)
        }
    }

    @Test func tableDoesNotStartWithoutRoomForTitleHeaderAndOneRow() {
        // Queda poco sitio tras el bloque: la tabla entera pasa a la página siguiente.
        let items: [MedicalFlowItem] = [.block(id: "a", height: 560, startsPage: false), table("t", rows: 3)]
        let pages = MedicalReportPaginator.paginate(items, contentHeight: content, spacing: spacing)
        #expect(pages.count == 2)
        #expect(pages[0].map(\.id) == ["a"])
        #expect(pages[1].map(\.id) == ["t"])
    }

    @Test func tableStartsOnTheCurrentPageWhenTitleHeaderAndOneRowFit() {
        let items: [MedicalFlowItem] = [.block(id: "a", height: 500, startsPage: false), table("t", rows: 10)]
        let pages = MedicalReportPaginator.paginate(items, contentHeight: content, spacing: spacing)
        #expect(pages[0].map(\.id) == ["a", "t"])
        guard case .rows(let first, _) = pages[0][1].kind else { Issue.record("no es tabla"); return }
        #expect(first.lowerBound == 0 && first.count >= 1 && first.count < 10)
        #expect(rows(of: "t", in: pages).reduce(0) { $0 + $1.count } == 10)
    }

    @Test func blocksMoveToTheNextPageAndStartsPageIsHonoured() {
        let items: [MedicalFlowItem] = [
            .block(id: "a", height: 400, startsPage: false), .block(id: "b", height: 250, startsPage: false),
            .block(id: "c", height: 50, startsPage: true), .block(id: "d", height: 50, startsPage: false),
        ]
        let pages = MedicalReportPaginator.paginate(items, contentHeight: content, spacing: spacing)
        #expect(pages.map { $0.map(\.id) } == [["a"], ["b"], ["c", "d"]])
    }

    @Test func gridWithoutHeaderAndEmptyTablesBehave() {
        let grid = MedicalFlowItem.table(id: "daily", titleHeight: 40, continuationTitleHeight: 16, headerHeight: 0,
                                         rowHeights: [Double](repeating: 84, count: 13), startsPage: true)
        let empty = MedicalFlowItem.table(id: "empty", titleHeight: 40, continuationTitleHeight: 16, headerHeight: 0,
                                          rowHeights: [], startsPage: false)
        let pages = MedicalReportPaginator.paginate([.block(id: "a", height: 100, startsPage: false), grid, empty],
                                                    contentHeight: content, spacing: spacing)
        #expect(pages.first?.map(\.id) == ["a"])
        #expect(rows(of: "daily", in: pages).reduce(0) { $0 + $1.count } == 13)
        #expect(rows(of: "empty", in: pages).isEmpty)
    }

    @Test func aRowTallerThanThePageStillGetsPlaced() {
        let giant = MedicalFlowItem.table(id: "g", titleHeight: 10, continuationTitleHeight: 10, headerHeight: 0,
                                          rowHeights: [800, 20], startsPage: false)
        let pages = MedicalReportPaginator.paginate([giant], contentHeight: content, spacing: spacing)
        #expect(rows(of: "g", in: pages) == [0..<1, 1..<2])
    }

    @Test func noRowIsLostOrRepeatedForManyShapes() {
        for rowCount in [1, 2, 7, 29, 30, 31, 118] {
            for rowHeight in [17.0, 27.0, 84.0] {
                let items: [MedicalFlowItem] = [
                    .block(id: "s", height: 560, startsPage: false), table("x", rows: rowCount, rowHeight: rowHeight),
                    table("y", rows: rowCount, rowHeight: rowHeight),
                ]
                let pages = MedicalReportPaginator.paginate(items, contentHeight: content, spacing: spacing)
                for id in ["x", "y"] {
                    let ranges = rows(of: id, in: pages)
                    #expect(ranges.reduce(0) { $0 + $1.count } == rowCount, "\(id) \(rowCount)×\(rowHeight)")
                    #expect(ranges == ranges.sorted { $0.lowerBound < $1.lowerBound })
                }
            }
        }
    }

    // MARK: Flujo del documento

    @Test func flowFollowsTheDocumentAndSkipsMissingSections() async throws {
        let full = MedicalReportBuilder.build(await MedicalReportFixtures.input())
        let ids = MedicalReportFlow.items(for: full).map(\.id)
        #expect(ids.first == "summary" && ids[1] == "agp")
        #expect(ids.contains("daily") && ids.contains("meals") && ids.contains("nights"))
        #expect(ids.last == "method")

        let bare = MedicalReportBuilder.build(await MedicalReportFixtures.input(
            options: MedicalReportOptions(meals: false, sleepActivity: false, exercise: false, bodyComposition: false, notes: false)))
        let bareIDs = MedicalReportFlow.items(for: bare).map(\.id)
        #expect(!bareIDs.contains("meals") && !bareIDs.contains("nights") && !bareIDs.contains("notes"))
        #expect(bareIDs.contains("agpTable") && bareIDs.contains("weekly"))
    }

    @Test func summaryFitsOnPageOneAndTheNinetyDayGridSpansPages() async throws {
        #expect(Double(MedicalReportFlow.summaryHeight) <= Double(MedicalPDFLayout.contentHeight))
        let rows = MedicalReportFlow.dailyRows(90)
        #expect(rows.count == 13)
        let pages = MedicalReportPaginator.paginate(
            [.table(id: "daily", titleHeight: 40, continuationTitleHeight: 16, headerHeight: 0, rowHeights: rows, startsPage: true)],
            contentHeight: Double(MedicalPDFLayout.contentHeight), spacing: Double(MedicalPDFLayout.spacing))
        #expect(pages.count == 2)
    }
}
