//
//  TarGzWriter.swift
//  MeasureGo
//
//  Native replacement for the lzip plugin Unity used: packs a directory into
//  a ustar tar and gzips it (directory contents at the archive root, matching
//  ZipCompressor.CompressDirectory's output consumed by the portal).
//

import Foundation
import Compression

enum TarGzWriter {

    enum TarError: Error {
        case compressionFailed
    }

    /// Creates a .tar.gz of the directory's contents at `outputURL`.
    static func createArchive(of directory: URL, to outputURL: URL) throws {
        let tarData = try tar(directory: directory)
        let gzData = try gzip(tarData)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try gzData.write(to: outputURL, options: .atomic)
    }

    // MARK: - tar (ustar)

    private static func tar(directory: URL) throws -> Data {
        var data = Data()
        try appendEntries(of: directory, relativePath: "", to: &data)
        data.append(Data(count: 1024)) // two zero blocks terminate the archive
        return data
    }

    private static func appendEntries(of dir: URL, relativePath: String, to data: inout Data) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let path = relativePath.isEmpty
                ? item.lastPathComponent
                : relativePath + "/" + item.lastPathComponent
            if isDir {
                data.append(header(path: path + "/", size: 0, typeFlag: 0x35, mode: 0o755)) // '5' directory
                try appendEntries(of: item, relativePath: path, to: &data)
            } else {
                let fileData = try Data(contentsOf: item)
                data.append(header(path: path, size: fileData.count, typeFlag: 0x30, mode: 0o644)) // '0' file
                data.append(fileData)
                let padding = (512 - fileData.count % 512) % 512
                if padding > 0 { data.append(Data(count: padding)) }
            }
        }
    }

    private static func header(path: String, size: Int, typeFlag: UInt8, mode: Int) -> Data {
        var h = [UInt8](repeating: 0, count: 512)

        func write(_ string: String, at offset: Int, maxLength: Int) {
            let bytes = Array(string.utf8.prefix(maxLength))
            h.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }

        write(path, at: 0, maxLength: 100)
        write(String(format: "%07o", mode), at: 100, maxLength: 8)    // mode
        write(String(format: "%07o", 0), at: 108, maxLength: 8)       // uid
        write(String(format: "%07o", 0), at: 116, maxLength: 8)       // gid
        write(String(format: "%011o", size), at: 124, maxLength: 12)  // size
        write(String(format: "%011o", Int(Date().timeIntervalSince1970)), at: 136, maxLength: 12)
        for i in 148..<156 { h[i] = 0x20 } // checksum field = spaces while computing
        h[156] = typeFlag
        write("ustar", at: 257, maxLength: 6) // magic (with trailing NUL)
        h[263] = 0x30 // version "00"
        h[264] = 0x30

        let checksum = h.reduce(0) { $0 + Int($1) }
        write(String(format: "%06o", checksum), at: 148, maxLength: 6)
        h[154] = 0x00
        h[155] = 0x20

        return Data(h)
    }

    // MARK: - gzip

    private static func gzip(_ input: Data) throws -> Data {
        let deflated = try deflate(input)
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        out.append(deflated)
        var crc = crc32(input).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: input.count).littleEndian
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }

    /// Raw DEFLATE via the Compression framework (COMPRESSION_ZLIB emits a
    /// bare deflate stream, which is exactly what the gzip container needs).
    private static func deflate(_ input: Data) throws -> Data {
        let dstCapacity = input.count + input.count / 2 + 1024
        var dst = Data(count: dstCapacity)
        let written = dst.withUnsafeMutableBytes { dstPtr in
            input.withUnsafeBytes { srcPtr in
                compression_encode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!, dstCapacity,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw TarError.compressionFailed }
        dst.removeSubrange(written..<dst.count)
        return dst
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
