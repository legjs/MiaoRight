import MiaoRightShared
import SwiftUI

struct FavoriteSnippetsPreferencesView: View {
    @State private var history = ClipboardHistoryService.shared
    @State private var text = ""
    @State private var feedback: String?
    @State private var failed = false

    var body: some View {
        DisclosureGroup(L10n.text("常用文字", "Text Snippets")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("保存常用地址、链接或回复。在剪贴板侧边栏切换到“收藏”即可找到。", "Save addresses, links or replies, then find them under Favorites in the clipboard sidebar."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.system(size: 13)).frame(minHeight: 80, maxHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
                    .accessibilityLabel(L10n.text("常用文字内容", "Snippet Content"))
                HStack {
                    Button(L10n.text("保存到收藏", "Save to Favorites")) {
                        if history.addFavoriteText(text) {
                            text = ""; failed = false; feedback = L10n.text("已保存到收藏。", "Saved to Favorites.")
                        } else { failed = true; feedback = history.feedback }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 10_000)
                    Spacer()
                    Text(L10n.text("\(history.items.filter(\.isFavorite).count) 条收藏", "\(history.items.filter(\.isFavorite).count) favorites"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if text.count > 10_000 { Text(L10n.text("最多保存 10000 字。", "Use at most 10,000 characters.")).font(.system(size: 12)).foregroundStyle(.red) }
                if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(failed ? Color.red : Color.secondary) }
            }.padding(.vertical, 12)
        }.disclosureGroupStyle(PreferenceDisclosureStyle(icon: "star", summary: L10n.text("收藏常用内容，长期保留", "Keep frequently used content in Favorites")))
    }
}
