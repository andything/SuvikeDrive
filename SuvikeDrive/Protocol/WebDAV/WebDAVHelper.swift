//
//  WebDAVHelper.swift
//  SuvikeDrive
//
//  模块：WebDAV挂载通用静态工具类
//  功能：路径名称清洗、挂载点检测、URL处理、Finder刷新
//  归属：Protocol/WebDAV
//  依赖：无外部状态，纯静态方法，提供给WebDAVMounter调用
//

import Foundation

enum WebDAVHelper {
    /// 挂载卷名称清洗，过滤macOS路径非法字符
    static func sanitizeVolumeName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    /// 判断目标路径是否为有效挂载点
    static func isMountedPath(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }

        var statBuf = stat()
        if stat(path, &statBuf) != 0 {
            return false
        }
        let parentPath = (path as NSString).deletingLastPathComponent
        var parentStat = stat()
        guard stat(parentPath, &parentStat) == 0 else {
            return false
        }
        return statBuf.st_dev != parentStat.st_dev
    }

    /// URL追加端口（不存在端口时填充）
    static func addPortToURL(_ urlString: String, port: Int) -> String {
        guard let url = URL(string: urlString), url.port == nil else {
            return urlString
        }
        guard var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return urlString
        }
        comp.port = port
        return comp.string ?? urlString
    }

    /// URL标准化：自动补齐 http/https
    static func normalizeHTTPSUrl(raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespaces)
        if str.starts(with: "http://") {
            str = str.replacingOccurrences(of: "http://", with: "https://")
        }
        if !str.starts(with: "http://") && !str.starts(with: "https://") {
            str = "https://\(str)"
        }
        return str
    }

    /// 主动刷新Finder窗口
    static func refreshFinder() {
        // 使用系统事件发送刷新命令
        let script = """
        tell application "Finder"
            activate
            set theWindows to every window
            repeat with aWindow in theWindows
                try
                    update aWindow
                end try
            end repeat
        end tell
        """
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }
}
