import SwiftUI

struct ResultPage {
    static let size = 50
    let count: Int
    let index: Int

    init(count: Int, requestedIndex: Int) {
        self.count = max(0, count)
        let lastIndex = (max(1, self.count) - 1) / Self.size
        index = min(max(0, requestedIndex), lastIndex)
    }

    var range: Range<Int> {
        let start = index * Self.size
        return start..<min(start + Self.size, count)
    }

    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { range.upperBound < count }
}

/// Bounds rendered rows while keeping selection in the owning feature view.
struct PagedResults<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row
    @State private var pageIndex = 0

    var body: some View {
        let page = ResultPage(count: items.count, requestedIndex: pageIndex)
        let pageItems = items[page.range]
        VStack(spacing: 10) {
            if !items.isEmpty {
                HStack {
                    Text("Showing \((page.range.lowerBound + 1).formatted())–\(page.range.upperBound.formatted()) of \(items.count.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if items.count > ResultPage.size {
                        Button("Previous") { pageIndex = page.index - 1 }
                            .disabled(!page.hasPrevious)
                        Button("Next") { pageIndex = page.index + 1 }
                            .disabled(!page.hasNext)
                    }
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(pageItems) { item in
                        row(item)
                        if item.id != pageItems.last?.id { Divider() }
                    }
                }
            }
            .id(page.index)
            .frame(height: 350)
        }
        .onChange(of: items.count) { _, _ in pageIndex = 0 }
    }
}
