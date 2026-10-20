import Foundation
import PDFKit

struct ClaudeMaterials {
    let root: URL
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clipboard AI Solver/ClaudeMaterials")) { self.root = root }
    private func url(_ id: String) throws -> URL {
        guard id.range(of: "^local-[0-9A-Fa-f-]{36}\\.(pdf|txt|md)$", options: .regularExpression) != nil else { throw SolverFailure(message: "로컬 자료 식별자가 올바르지 않습니다.") }
        return root.appendingPathComponent(id)
    }
    func data(_ id: String) throws -> Data {
        let path = try url(id)
        let values = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, (1...12_000_000).contains(size) else { throw SolverFailure(message: "Claude 자료는 파일당 12 MB 이하의 일반 파일이어야 합니다.") }
        let data = try Data(contentsOf: path)
        guard data.count <= 12_000_000 else { throw SolverFailure(message: "Claude 자료 크기를 확인하세요.") }
        return data
    }
    private func validate(_ data: Data, ext: String) throws {
        if ext == "pdf" {
            guard let document = PDFDocument(data: data), !document.isLocked else { throw SolverFailure(message: "암호화되었거나 읽을 수 없는 PDF입니다.") }
        } else {
            guard let text = String(data: data, encoding: .utf8), !normalized(text).isEmpty else { throw SolverFailure(message: "TXT/MD는 비어 있지 않은 UTF-8 파일이어야 합니다.") }
        }
    }
    func add(_ source: URL) throws -> ManagedFile {
        let ext = source.pathExtension.lowercased()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard ["pdf", "txt", "md"].contains(ext), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (1...12_000_000).contains(size) else { throw SolverFailure(message: "PDF/TXT/MD 파일(파일당 12 MB 이하)을 선택하세요.") }
        let bytes = try Data(contentsOf: source)
        guard bytes.count <= 12_000_000 else { throw SolverFailure(message: "Claude 자료는 파일당 12 MB 이하입니다.") }
        try validate(bytes, ext: ext)
        let id = "local-" + UUID().uuidString + "." + ext
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = try url(id)
        try bytes.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return ManagedFile(id: id, filename: source.lastPathComponent, status: "준비됨", attached: true, byteCount: bytes.count)
    }
    func remove(_ id: String) throws {
        let path = try url(id)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
    func status(_ file: ManagedFile) throws -> String {
        try validate(data(file.id), ext: file.id.hasSuffix(".pdf") ? "pdf" : "txt")
        return "준비됨"
    }
    func input(_ file: ManagedFile) throws -> [String: Any] {
        let bytes = try data(file.id)
        if file.id.hasSuffix(".pdf") {
            return ["type": "document", "title": file.filename, "source": ["type": "base64", "media_type": "application/pdf", "data": bytes.base64EncodedString()]]
        }
        guard let text = String(data: bytes, encoding: .utf8) else { throw SolverFailure(message: "첨부 텍스트를 읽지 못했습니다.") }
        return ["type": "document", "title": file.filename, "source": ["type": "text", "media_type": "text/plain", "data": text]]
    }
}
