//
//  CloudAPI.swift
//  MeasureGo
//
//  Portal HTTP layer — port of Unity's ProjectCloud.cs / ResourceCloud.cs.
//

import Foundation
import UIKit

enum CloudError: LocalizedError {
    case notAuthenticated
    case http(Int, String)
    case allRetriesFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not logged in."
        case .http(let code, let body):
            return "Server error \(code): \(body.prefix(200))"
        case .allRetriesFailed(let file):
            return "Failed to upload \(file) after several attempts."
        }
    }
}

enum CloudAPI {

    private static let baseURL = "https://admin.lathammeasure.com/api/v1"
    static let maxRetries = 3

    /// PUT /projects/{id} with the project contract JSON.
    static func putProject(id: String, jsonData: Data) async throws {
        guard let token = AuthManager.shared.token, !token.isEmpty else {
            throw CloudError.notAuthenticated
        }
        var request = URLRequest(url: URL(string: "\(baseURL)/projects/\(id)")!)
        request.httpMethod = "PUT"
        request.httpBody = jsonData
        applyCommonHeaders(&request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CloudError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// PUT /resources/{id}/{revision}/file as multipart/form-data ("file"
    /// part), with Unity's 3-retry policy.
    static func putResourceFile(resourceId: String, revision: Int, fileURL: URL) async throws {
        guard let token = AuthManager.shared.token, !token.isEmpty else {
            throw CloudError.notAuthenticated
        }

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let mime = mimeType(for: fileURL)

        var lastError: Error = CloudError.allRetriesFailed(fileName)
        for _ in 0..<maxRetries {
            do {
                try await putMultipart(
                    url: URL(string: "\(baseURL)/resources/\(resourceId)/\(revision)/file")!,
                    token: token, fileData: fileData, fileName: fileName, mimeType: mime
                )
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func putMultipart(
        url: URL, token: String, fileData: Data, fileName: String, mimeType: String
    ) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        applyCommonHeaders(&request, token: token)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CloudError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private static func applyCommonHeaders(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-BAI-CORRELATION-ID")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
    }

    /// Unity: "{productName}/{version}/({operatingSystem}; {deviceModel})"
    private static var userAgent: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MeasureGo"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let model = UIDevice.current.model
        return "\(name)/\(version)/(\(os); \(model))"
    }

    /// Same mapping as Unity's ResourceCloud.GetMimeType (including its quirk:
    /// ".gz" isn't matched, so the archive goes up as octet-stream).
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "csv": return "text/plain"
        case "zip", "gzip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
