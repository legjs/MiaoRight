import Foundation
import MiaoRightShared
import SwiftUI

struct ReleaseNoteBlock: Identifiable, Equatable {
    enum Kind: Equatable { case heading, bullet, paragraph }
    let id: Int
    let kind: Kind
    let text: String
}

enum ReleaseNotesParser {
    static func blocks(from markdown: String, english: Bool) -> [ReleaseNoteBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let selected = selectedLines(lines, english: english)
        return selected.enumerated().compactMap { index, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("# "), !line.hasPrefix("## ") else { return nil }
            if line.hasPrefix("### ") {
                return ReleaseNoteBlock(id: index, kind: .heading, text: String(line.dropFirst(4)))
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return ReleaseNoteBlock(id: index, kind: .bullet, text: String(line.dropFirst(2)))
            }
            return ReleaseNoteBlock(id: index, kind: .paragraph, text: line)
        }
    }

    private static func selectedLines(_ lines: [String], english: Bool) -> [String] {
        let target = english ? "english" : "中文"
        let other = english ? "中文" : "english"
        guard let start = lines.firstIndex(where: { isTopLevelHeading($0, matching: target) }) else {
            return lines
        }
        let afterStart = lines.index(after: start)
        let end = lines[afterStart...].firstIndex(where: {
            isTopLevelHeading($0, matching: other) || isAnyTopLevelHeading($0)
        }) ?? lines.endIndex
        return Array(lines[afterStart..<end])
    }

    private static func isAnyTopLevelHeading(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("## ")
    }

    private static func isTopLevelHeading(_ line: String, matching text: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("## ") && trimmed.contains(text.lowercased())
    }
}

struct ReleaseNotesView: View {
    let markdown: String?

    private var blocks: [ReleaseNoteBlock] {
        guard let markdown else { return [] }
        return ReleaseNotesParser.blocks(from: markdown, english: L10n.isEnglish)
    }

    var body: some View {
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("本次更新", "What’s New"))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.bottom, 1)
                ForEach(blocks) { block in
                    switch block.kind {
                    case .heading:
                        Text(block.text)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.top, 3)
                    case .bullet:
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("•").foregroundStyle(.secondary)
                            Text(inlineMarkdown(block.text)).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    case .paragraph:
                        Text(inlineMarkdown(block.text))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
