import SwiftUI

/// Las ocho cards en orden, cada una con enlace a su detalle si hay algo que mostrar.
struct ReportCardsList: View {
    let content: ReportContent
    let namespace: Namespace.ID

    var body: some View {
        ForEach(ReportRoute.allCases) { route in
            let hasDetail = route.hasDetail(content)
            ReportCardLink(route: route, isEnabled: hasDetail, namespace: namespace) {
                ReportCard(
                    title: route.title,
                    systemImage: route.systemImage,
                    caption: ReportCardContent.caption(route, content: content),
                    showsDisclosure: hasDetail
                ) {
                    ReportCardContent(route: route, content: content)
                }
            }
        }
    }
}
