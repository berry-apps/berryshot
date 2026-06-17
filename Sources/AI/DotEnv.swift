import Foundation

public struct DotEnv {
    nonisolated(unsafe) public static var env: [String: String] = [:]
    
    public static func load() {
        var searchPaths: [URL] = []
        
        // 1. Bundle Resource
        if let bundlePath = Bundle.main.path(forResource: ".env", ofType: nil) {
            searchPaths.append(URL(fileURLWithPath: bundlePath))
        }
        
        // 2. Current Working Directory
        let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        searchPaths.append(cwdPath)
        
        // 3. User Home Directory
        let homePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".berryshot.env")
        searchPaths.append(homePath)
        
        for path in searchPaths {
            if let content = try? String(contentsOf: path, encoding: .utf8) {
                parse(content: content)
                print("Loaded .env from \(path.path)")
            }
        }
    }
    
    private static func parse(content: String) {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                
                // Remove surrounding quotes if any
                if value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'") {
                    value = String(value.dropFirst().dropLast())
                }
                
                env[key] = value
                setenv(key, value, 1) // Also set to process environment
            }
        }
    }
    
    public static func get(_ key: String) -> String? {
        if let val = ProcessInfo.processInfo.environment[key] {
            return val
        }
        return env[key]
    }
}
