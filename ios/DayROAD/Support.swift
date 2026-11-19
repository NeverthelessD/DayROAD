import Foundation

// 저장 위치 · 기록
//
// Application Support/DayROAD : data.json(맥과 같은 모양의 사본) · log.txt
// 앱 그룹 폴더(group.com.neverthelessd.dayroad.iphone)/widget : widget.json · actions.jsonl — 위젯과 같이 써요
// 진짜 할 일 파일은 iCloud Drive › DayROAD › data.json (Cloud.swift). 맥 DayROAD 와 같은 파일이에요.

enum Paths {
    static let groupID = "group.com.neverthelessd.dayroad.iphone"

    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("DayROAD", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static func file(_ name: String) -> URL { support.appendingPathComponent(name) }

    /// 위젯과 같이 쓰는 폴더. 앱 그룹을 못 쓰면(서명 문제) nil — 그때는 위젯만 빠지고 앱은 그대로 돼요.
    static let widgetDir: URL? = {
        guard let g = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        let u = g.appendingPathComponent("widget", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
}

/// 진단 기록: 설정 › 진단 정보 보기
enum Log {
    private static let queue = DispatchQueue(label: "dayroad.log")
    private static let url = Paths.file("log.txt")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        print(line, terminator: "")
        queue.async {
            let data = Data(line.utf8)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > 300_000,
               let all = try? Data(contentsOf: url) {
                try? all.suffix(150_000).write(to: url)
            }
        }
    }

    static func text() -> String {
        queue.sync { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    }
}

enum Fmt {
    static func randomID(_ n: Int = 6) -> String {
        // 맥 엔진과 같은 모양 (16진수 2n글자)
        (0..<n).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// 받침이 있으면 "을", 없으면 "를"
    static func eul(_ word: String) -> String {
        guard let v = word.unicodeScalars.last?.value, v >= 0xAC00 && v <= 0xD7A3 else { return "을(를)" }
        return (v - 0xAC00) % 28 != 0 ? "을" : "를"
    }
}
