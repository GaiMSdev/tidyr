import Foundation

// Checks whether a folder is safe to let the AI reorganize.
// Returns a warning if sensitive app/project structure is detected.
struct SafetyChecker {

    enum Risk {
        case safe
        case warning(title: String, detail: String)  // user can still proceed
        case danger(title: String, detail: String)   // strongly discouraged
    }

    static func check(folder: URL) -> Risk {

        let path       = folder.path
        let folderName = folder.lastPathComponent
        let contents   = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let contentSet = Set(contents.map { $0.lowercased() })

        // 1. System and protected paths
        let protectedPrefixes = [
            "/System", "/usr", "/bin", "/sbin", "/etc",
            "/var", "/private", "/Library",
            "\(NSHomeDirectory())/Library"
        ]
        for prefix in protectedPrefixes {
            if path.hasPrefix(prefix) {
                return .danger(
                    title: "This is a protected system folder",
                    detail: "\"\(folderName)\" is inside a system or library directory that macOS depends on. Reorganizing it could break apps or damage macOS. Please choose a different folder."
                )
            }
        }

        // 2. The folder itself is an internal/hidden tool folder
        let dangerousFolderNames: Set<String> = [
            ".git", ".obsidian", "node_modules", ".vscode", ".idea",
            "pods", "deriveddata", ".build", "__pycache__", ".npm",
            ".yarn", ".gradle", ".cargo", "vendor"
        ]
        if dangerousFolderNames.contains(folderName.lowercased()) {
            return .danger(
                title: "This folder is internal to an app or tool",
                detail: "\"\(folderName)\" is a special folder used internally by software. Reorganizing its contents would likely break the app or tool that owns it."
            )
        }

        // 3. App bundles (.app, .framework, etc.)
        let appLikeExtensions = ["app", "framework", "plugin", "kext", "bundle"]
        if appLikeExtensions.contains(folder.pathExtension.lowercased()) {
            return .danger(
                title: "This is an application bundle",
                detail: "\"\(folderName)\" is an app or framework. Its internal structure is fixed by Apple — any change will corrupt it and make it unlaunchable."
            )
        }

        // 4. Git repository
        if contentSet.contains(".git") {
            return .warning(
                title: "This folder is a Git repository",
                detail: "Moving or renaming files here without using Git commands can confuse version control and cause you to lose history or break other contributors' copies. Proceed only if you understand the risk."
            )
        }

        // 5. Xcode project
        let hasXcodeProject = contents.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
        if hasXcodeProject {
            return .warning(
                title: "This looks like an Xcode project",
                detail: "Xcode projects depend on exact file paths. Moving or renaming source files without also updating the project will cause build errors. Use Xcode's own rename tools instead."
            )
        }

        // 6. Node.js project
        if contentSet.contains("package.json") || contentSet.contains("package-lock.json") {
            return .warning(
                title: "This looks like a Node.js project",
                detail: "JavaScript files import each other by exact path. Renaming or moving files here will break those imports and stop the project from running."
            )
        }

        // 7. Python project
        if contentSet.contains("setup.py") || contentSet.contains("pyproject.toml") {
            return .warning(
                title: "This looks like a Python project",
                detail: "Python packages depend on their folder structure for imports to work. Reorganizing here could break the project."
            )
        }

        // 8. Other programming projects
        let projectIndicators: [(String, String)] = [
            ("cargo.toml",         "Rust project"),
            ("go.mod",             "Go module"),
            ("pom.xml",            "Maven/Java project"),
            ("build.gradle",       "Gradle project"),
            ("composer.json",      "PHP/Composer project"),
            ("gemfile",            "Ruby project"),
            ("mix.exs",            "Elixir project"),
            ("pubspec.yaml",       "Flutter/Dart project"),
            ("dockerfile",         "Docker configuration"),
            ("docker-compose.yml", "Docker Compose setup"),
            ("podfile",            "CocoaPods project"),
        ]
        for (file, name) in projectIndicators {
            if contentSet.contains(file) {
                return .warning(
                    title: "This looks like a \(name)",
                    detail: "This folder has a specific structure that the tooling depends on. Reorganizing it could break builds, imports, or deployments."
                )
            }
        }

        // 9. Obsidian vault — safe to organize, Tidyr repairs links automatically
        if contentSet.contains(".obsidian") {
            return .warning(
                title: "This is an Obsidian vault",
                detail: "Tidyr will automatically repair wikilinks and canvas references after any moves or renames. The .obsidian folder (settings and plugins) will not be touched."
            )
        }

        return .safe
    }
}
