import Foundation

struct ObsidianLinkRepairer {

    struct RepairResult {
        let filesModified: Int
        let linksRepaired: Int
        static let empty = RepairResult(filesModified: 0, linksRepaired: 0)

        static func + (lhs: RepairResult, rhs: RepairResult) -> RepairResult {
            RepairResult(filesModified: lhs.filesModified + rhs.filesModified,
                         linksRepaired: lhs.linksRepaired + rhs.linksRepaired)
        }
    }

    // Forward repair — called after apply
    static func repair(vaultURL: URL, operations: [UndoOperation]) throws -> RepairResult {
        let usesPathLinks = readUsesPathLinks(vaultURL: vaultURL)
        var total = RepairResult.empty
        for op in operations {
            for (old, new) in refs(for: op, in: vaultURL, usesPathLinks: usesPathLinks) {
                total = total + (try scan(vaultURL: vaultURL, old: old, new: new))
            }
        }
        return total
    }

    // Reverse repair — called on undo (swaps old/new for each operation)
    static func reverseRepair(vaultURL: URL, operations: [UndoOperation]) throws -> RepairResult {
        let reversed: [UndoOperation] = operations.reversed().map {
            switch $0 {
            case .moved(let orig, let dest):   return .moved(originalURL: dest, movedToURL: orig)
            case .renamed(let orig, let dest): return .renamed(originalURL: dest, renamedToURL: orig)
            case .createdFolder(let url):      return .createdFolder(url)
            }
        }
        return try repair(vaultURL: vaultURL, operations: reversed)
    }

    // MARK: - Internals

    private static func refs(
        for op: UndoOperation, in vaultURL: URL, usesPathLinks: Bool
    ) -> [(old: String, new: String)] {
        switch op {
        case .renamed(let from, let to):
            let isMD  = from.pathExtension.lowercased() == "md"
            // .md files: Obsidian omits extension in wikilinks, attachments keep it
            let oldName = isMD ? from.deletingPathExtension().lastPathComponent : from.lastPathComponent
            let newName = isMD ? to.deletingPathExtension().lastPathComponent   : to.lastPathComponent
            var pairs: [(String, String)] = []
            if oldName != newName { pairs.append((oldName, newName)) }
            if usesPathLinks {
                let oldPath = vaultRelative(url: from, vault: vaultURL, withExt: !isMD)
                let newPath = vaultRelative(url: to,   vault: vaultURL, withExt: !isMD)
                if oldPath != newPath { pairs.append((oldPath, newPath)) }
            }
            return pairs

        case .moved(let from, let to):
            guard usesPathLinks else { return [] }
            let isMD    = from.pathExtension.lowercased() == "md"
            let oldPath = vaultRelative(url: from, vault: vaultURL, withExt: !isMD)
            let newPath = vaultRelative(url: to,   vault: vaultURL, withExt: !isMD)
            return oldPath != newPath ? [(oldPath, newPath)] : []

        case .createdFolder:
            return []
        }
    }

    // Scans .md files for wikilink replacements, and .canvas files for path replacements
    private static func scan(vaultURL: URL, old: String, new: String) throws -> RepairResult {
        guard old != new else { return .empty }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return .empty }

        let escapedOld = NSRegularExpression.escapedPattern(for: old)
        // Wikilink pattern: [[old or ![[old followed by ]], |, or #
        guard let wikiRegex = try? NSRegularExpression(
            pattern: "(!?\\[\\[)" + escapedOld + "(?=[\\]\\|#])",
            options: .caseInsensitive
        ) else { return .empty }
        // Canvas pattern: "file":"old.md" (always vault-relative with .md extension)
        let canvasOld = old.hasSuffix(".md") ? old : old + ".md"
        let canvasNew = new.hasSuffix(".md") ? new : new + ".md"
        let escapedCanvasOld = NSRegularExpression.escapedPattern(for: canvasOld)
        let canvasRegex = try? NSRegularExpression(
            pattern: #""file"\s*:\s*""# + escapedCanvasOld + #"""#,
            options: .caseInsensitive
        )

        let escapedNew = new.replacingOccurrences(of: "$", with: "\\$")
        let wikiTemplate = "$1\(escapedNew)"

        var filesModified = 0
        var linksRepaired = 0

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()

            if ext == "md" {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let range = NSRange(content.startIndex..., in: content)
                let count = wikiRegex.numberOfMatches(in: content, range: range)
                guard count > 0 else { continue }
                let updated = wikiRegex.stringByReplacingMatches(in: content, range: range, withTemplate: wikiTemplate)
                try updated.write(to: fileURL, atomically: true, encoding: .utf8)
                filesModified += 1
                linksRepaired += count

            } else if ext == "canvas", let regex = canvasRegex {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let range = NSRange(content.startIndex..., in: content)
                let count = regex.numberOfMatches(in: content, range: range)
                guard count > 0 else { continue }
                let escapedCanvasNew = canvasNew.replacingOccurrences(of: "$", with: "\\$")
                let template = #""file":""# + escapedCanvasNew + #"""#
                let updated = regex.stringByReplacingMatches(in: content, range: range, withTemplate: template)
                try updated.write(to: fileURL, atomically: true, encoding: .utf8)
                filesModified += 1
                linksRepaired += count
            }
        }

        return RepairResult(filesModified: filesModified, linksRepaired: linksRepaired)
    }

    private static func readUsesPathLinks(vaultURL: URL) -> Bool {
        let appJSON = vaultURL.appendingPathComponent(".obsidian/app.json")
        guard
            let data = try? Data(contentsOf: appJSON),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let format = json["newLinkFormat"] as? String
        else { return false }
        return format != "shortest"
    }

    private static func vaultRelative(url: URL, vault: URL, withExt: Bool) -> String {
        var path = url.path
        let base = vault.path + "/"
        if path.hasPrefix(base) { path = String(path.dropFirst(base.count)) }
        return withExt ? path : (path as NSString).deletingPathExtension
    }
}
