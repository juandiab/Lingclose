/// Reparte las piezas del reporte en páginas de alto fijo (T-34). Puro y determinista.
///
/// - Un bloque indivisible que no cabe en lo que queda de página pasa a la siguiente.
/// - Una tabla empieza en la página actual solo si caben su título, su cabecera y al menos una fila; si no, pasa a la
///   siguiente. Sus filas se reparten sin partir ninguna y cada tramo repite título y cabecera.
/// - Nada se pierde ni se repite: las filas de los tramos de una tabla son una partición de `0..<n`.
enum MedicalReportPaginator {
    static func paginate(_ items: [MedicalFlowItem], contentHeight: Double, spacing: Double) -> [[MedicalPageSlice]] {
        var pages: [[MedicalPageSlice]] = [[]]
        var used = 0.0

        func newPage() {
            pages.append([])
            used = 0
        }
        func append(_ slice: MedicalPageSlice) {
            used += (pages[pages.count - 1].isEmpty ? 0 : spacing) + slice.height
            pages[pages.count - 1].append(slice)
        }
        var isEmpty: Bool { pages[pages.count - 1].isEmpty }

        for item in items {
            switch item {
            case .block(let id, let height, let startsPage):
                if startsPage && !isEmpty { newPage() }
                let need = height + (isEmpty ? 0 : spacing)
                if need > contentHeight - used && !isEmpty { newPage() }
                append(MedicalPageSlice(id: id, kind: .block, height: height))

            case .table(let id, let titleHeight, let continuationTitleHeight, let headerHeight, let rowHeights, let startsPage):
                guard !rowHeights.isEmpty else { continue }
                if startsPage && !isEmpty { newPage() }
                var index = 0
                var isFirst = true
                while index < rowHeights.count {
                    let head = (isFirst ? titleHeight : continuationTitleHeight) + headerHeight
                    let gap = isEmpty ? 0 : spacing
                    let available = contentHeight - used - gap
                    if head + rowHeights[index] > available && !isEmpty {
                        newPage()
                        continue
                    }
                    var height = head
                    var count = 0
                    while index + count < rowHeights.count, count == 0 || height + rowHeights[index + count] <= available {
                        height += rowHeights[index + count]
                        count += 1
                    }
                    append(MedicalPageSlice(
                        id: id, kind: .rows(rows: index..<(index + count), isContinuation: !isFirst), height: height))
                    index += count
                    isFirst = false
                    if index < rowHeights.count { newPage() }
                }
            }
        }
        return pages.filter { !$0.isEmpty }
    }
}
