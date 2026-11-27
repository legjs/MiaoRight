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
    @State private var prefersEnglish = L10n.isEnglish

    private var blocks: [ReleaseNoteBlock] {
        guard let markdown else { return [] }
        return ReleaseNotesParser.blocks(from: markdown, english: prefersEnglish)
    }

    private var hasBothLanguages: Bool {
        guard let markdown else { return false }
        return markdown.localizedCaseInsensitiveContains("## 中文")
            && markdown.localizedCaseInsensitiveContains("## english")
    }

    var body: some View {
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(prefersEnglish ? "What’s New" : "本次更新")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 12)
                    if hasBothLanguages {
                        Picker("", selection: $prefersEnglish) {
                            Text("中文").tag(false)
                            Text("English").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
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
                            Text(plainText(block.text)).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    case .paragraph:
                        Text(plainText(block.text))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func plainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
    }
}
