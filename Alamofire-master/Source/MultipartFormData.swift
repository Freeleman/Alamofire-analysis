//
//  MultipartFormData.swift
//
//  Copyright (c) 2014-2018 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

#if os(iOS) || os(watchOS) || os(tvOS)
import MobileCoreServices
#elseif os(macOS)
import CoreServices
#endif

/// Constructs `multipart/form-data` for uploads within an HTTP or HTTPS body. There are currently two ways to encode
/// multipart form data. The first way is to encode the data directly in memory. This is very efficient, but can lead
/// to memory issues if the dataset is too large. The second way is designed for larger datasets and will write all the
/// data to a single file on disk with all the proper boundary segmentation. The second approach MUST be used for
/// larger datasets such as video content, otherwise your app may run out of memory when trying to encode the dataset.
///
/// For more information on `multipart/form-data` in general, please refer to the RFC-2388 and RFC-2045 specs as well
/// and the w3 form documentation.
///
/// - https://www.ietf.org/rfc/rfc2388.txt
/// - https://www.ietf.org/rfc/rfc2045.txt
/// - https://www.w3.org/TR/html401/interact/forms.html#h-17.13
open class MultipartFormData {
    // MARK: - Helper Types
    // 回车换行
    enum EncodingCharacters {
        static let crlf = "\r\n"
    }

    enum BoundaryGenerator {
        enum BoundaryType {
            // 起始: --分隔符\r\n
            // 中间: \r\n--分隔符\r\n
            // 结尾: \r\n--分隔符--\r\n
            case initial, encapsulated, final
        }
        /// 随机分隔符
        /// 随机两个32 位无符号整数, 转16 进制展示, 使用0 补足8 个字符, 加上前缀
        static func randomBoundary() -> String {
            let first = UInt32.random(in: UInt32.min...UInt32.max)
            let second = UInt32.random(in: UInt32.min...UInt32.max)

            return String(format: "alamofire.boundary.%08x%08x", first, second)
        }
        /// 生成分隔符Data 拼接数据用
        static func boundaryData(forBoundaryType boundaryType: BoundaryType, boundary: String) -> Data {
            let boundaryText: String

            switch boundaryType {
            case .initial:
                boundaryText = "--\(boundary)\(EncodingCharacters.crlf)"
            case .encapsulated:
                boundaryText = "\(EncodingCharacters.crlf)--\(boundary)\(EncodingCharacters.crlf)"
            case .final:
                boundaryText = "\(EncodingCharacters.crlf)--\(boundary)--\(EncodingCharacters.crlf)"
            }

            return Data(boundaryText.utf8)
        }
    }
    // 每一个表单数据对象
    class BodyPart {
        // 每个body 头
        let headers: HTTPHeaders
        // body 数据流
        let bodyStream: InputStream
        // 数据长度
        let bodyContentLength: UInt64
        // 两个变量控制数据前后分隔符类型, 最终编码时, 把bodyparts 数组头围对应开关打开, 两个都为false 代表中间数据
        // 开始分隔符
        var hasInitialBoundary = false
        // 结尾分隔符
        var hasFinalBoundary = false

        init(headers: HTTPHeaders, bodyStream: InputStream, bodyContentLength: UInt64) {
            self.headers = headers
            self.bodyStream = bodyStream
            self.bodyContentLength = bodyContentLength
        }
    }

    // MARK: - Properties

    /// Default memory threshold used when encoding `MultipartFormData`, in bytes.
    /// 默认编码数据, 最大10MB, 超过则把数据编码到磁盘临时文件中
    public static let encodingMemoryThreshold: UInt64 = 10_000_000

    /// The `Content-Type` header value containing the boundary used to generate the `multipart/form-data`.
    /// 多表单数据头部Content-Type, 定义multipart/form-data 与分隔符
    open lazy var contentType: String = "multipart/form-data; boundary=\(self.boundary)"
    
    /// The content length of all body parts used to generate the `multipart/form-data` not including the boundaries.
    /// 所有表单数据部分的data 大小, 不包括分隔符
    public var contentLength: UInt64 { bodyParts.reduce(0) { $0 + $1.bodyContentLength } }

    /// The boundary used to separate the body parts in the encoded form data.
    /// 分隔符
    public let boundary: String
    // 添加fileurl 类型的数据时用来操作文件使用, 以及将data 写入临时文件使用
    let fileManager: FileManager
    // 保存多表单数据的数组
    private var bodyParts: [BodyPart]
    // 追加表单数据出现错误
    private var bodyPartError: AFError?
    // buffer 大小, 默认1024Bytes
    private let streamBufferSize: Int

    // MARK: - Lifecycle

    /// Creates an instance.
    ///
    /// - Parameters:
    ///   - fileManager: `FileManager` to use for file operations, if needed.
    ///   - boundary: Boundary `String` used to separate body parts.
    public init(fileManager: FileManager = .default, boundary: String? = nil) {
        self.fileManager = fileManager
        self.boundary = boundary ?? BoundaryGenerator.randomBoundary()
        bodyParts = []

        //
        // The optimal read/write buffer size in bytes for input and output streams is 1024 (1KB). For more
        // information, please refer to the following article:
        //   - https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/Streams/Articles/ReadingInputStreams.html
        //
        streamBufferSize = 1024
    }

    // MARK: - Body Parts
    // 5 个方法追加, 3 种不同表单数据类型
    /// Creates a body part from the data and appends it to the instance.
    ///
    /// The body part data will be encoded using the following format:
    /// 格式
    /// - `Content-Disposition: form-data; name=#{name}; filename=#{filename}` (HTTP Header)
    /// - `Content-Type: #{mimeType}` (HTTP Header)
    /// - Encoded file data
    /// - Multipart form boundary
    ///
    /// - Parameters:
    ///   - data:     `Data` to encoding into the instance.
    ///   - name:     Name to associate with the `Data` in the `Content-Disposition` HTTP header.
    ///   - fileName: Filename to associate with the `Data` in the `Content-Disposition` HTTP header.
    ///   - mimeType: MIME type to associate with the data in the `Content-Type` HTTP header.
    /// 1.
    /// Data + name, 内存读取, 小文件, 可指定文件名字与mine 类型
    public func append(_ data: Data, withName name: String, fileName: String? = nil, mimeType: String? = nil) {
        let headers = contentHeaders(withName: name, fileName: fileName, mimeType: mimeType)
        let stream = InputStream(data: data)
        let length = UInt64(data.count)

        append(stream, withLength: length, headers: headers)
    }

    /// Creates a body part from the file and appends it to the instance.
    ///
    /// The body part data will be encoded using the following format:
    /// 格式
    /// - `Content-Disposition: form-data; name=#{name}; filename=#{generated filename}` (HTTP Header)
    /// - `Content-Type: #{generated mimeType}` (HTTP Header)
    /// - Encoded file data
    /// - Multipart form boundary
    ///
    /// The filename in the `Content-Disposition` HTTP header is generated from the last path component of the
    /// `fileURL`. The `Content-Type` HTTP header MIME type is generated by mapping the `fileURL` extension to the
    /// system associated MIME type.
    ///
    /// - Parameters:
    ///   - fileURL: `URL` of the file whose content will be encoded into the instance.
    ///   - name:    Name to associate with the file content in the `Content-Disposition` HTTP header.
    /// 2.
    /// fileurl + name 未指明文件名字, mine 类型, 根据fileurl 最后文件名与扩展名判断, 调用方法3
    public func append(_ fileURL: URL, withName name: String) {
        // 获取文件名与mime 类型, 若读取不到就记录错误并return
        let fileName = fileURL.lastPathComponent
        let pathExtension = fileURL.pathExtension

        if !fileName.isEmpty && !pathExtension.isEmpty {
            // 使用辅助函数获取mime 类型字符串
            let mime = mimeType(forPathExtension: pathExtension)
            // 调用方法3
            append(fileURL, withName: name, fileName: fileName, mimeType: mime)
        } else {
            setBodyPartError(withReason: .bodyPartFilenameInvalid(in: fileURL))
        }
    }

    /// Creates a body part from the file and appends it to the instance.
    ///
    /// The body part data will be encoded using the following format:
    /// 格式
    /// - Content-Disposition: form-data; name=#{name}; filename=#{filename} (HTTP Header)
    /// - Content-Type: #{mimeType} (HTTP Header)
    /// - Encoded file data
    /// - Multipart form boundary
    ///
    /// - Parameters:
    ///   - fileURL:  `URL` of the file whose content will be encoded into the instance.
    ///   - name:     Name to associate with the file content in the `Content-Disposition` HTTP header.
    ///   - fileName: Filename to associate with the file content in the `Content-Disposition` HTTP header.
    ///   - mimeType: MIME type to associate with the file content in the `Content-Type` HTTP header.
    /// 3.
    /// fileurl + name + 文件名 + mine 类型, 同2
    /// 上传大文件, 使用InputStream 读取暂存文件
    public func append(_ fileURL: URL, withName name: String, fileName: String, mimeType: String) {
        // 表单头
        let headers = contentHeaders(withName: name, fileName: fileName, mimeType: mimeType)

        //============================================================
        //                 Check 1 - is file URL?
        //============================================================
        // 1. 检测url 是否合法
        guard fileURL.isFileURL else {
            setBodyPartError(withReason: .bodyPartURLInvalid(url: fileURL))
            return
        }

        //============================================================
        //              Check 2 - is file URL reachable?
        //============================================================
        // 2. 检测文件url 是否可以访问
        #if !(os(Linux) || os(Windows))
        do {
            let isReachable = try fileURL.checkPromisedItemIsReachable()
            guard isReachable else {
                setBodyPartError(withReason: .bodyPartFileNotReachable(at: fileURL))
                return
            }
        } catch {
            // catch 异常记录返回
            setBodyPartError(withReason: .bodyPartFileNotReachableWithError(atURL: fileURL, error: error))
            return
        }
        #endif

        //============================================================
        //            Check 3 - is file URL a directory?
        //============================================================
        // 3. url 是否是目录, 目录直接返回
        var isDirectory: ObjCBool = false
        let path = fileURL.path

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue else {
            setBodyPartError(withReason: .bodyPartFileIsDirectory(at: fileURL))
            return
        }

        //============================================================
        //          Check 4 - can the file size be extracted?
        //============================================================
        // 4. 是否能获取文件大小
        let bodyContentLength: UInt64
        
        do {
            guard let fileSize = try fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber else {
                setBodyPartError(withReason: .bodyPartFileSizeNotAvailable(at: fileURL))
                return
            }

            bodyContentLength = fileSize.uint64Value
        } catch {
            setBodyPartError(withReason: .bodyPartFileSizeQueryFailedWithError(forURL: fileURL, error: error))
            return
        }

        //============================================================
        //       Check 5 - can a stream be created from file URL?
        //============================================================
        // 5. 是否能创建InputStream
        guard let stream = InputStream(url: fileURL) else {
            setBodyPartError(withReason: .bodyPartInputStreamCreationFailed(for: fileURL))
            return
        }
        // 调用方法5
        append(stream, withLength: bodyContentLength, headers: headers)
    }

    /// Creates a body part from the stream and appends it to the instance.
    ///
    /// The body part data will be encoded using the following format:
    /// 格式
    /// - `Content-Disposition: form-data; name=#{name}; filename=#{filename}` (HTTP Header)
    /// - `Content-Type: #{mimeType}` (HTTP Header)
    /// - Encoded stream data
    /// - Multipart form boundary
    ///
    /// - Parameters:
    ///   - stream:   `InputStream` to encode into the instance.
    ///   - length:   Length, in bytes, of the stream.
    ///   - name:     Name to associate with the stream content in the `Content-Disposition` HTTP header.
    ///   - fileName: Filename to associate with the stream content in the `Content-Disposition` HTTP header.
    ///   - mimeType: MIME type to associate with the stream content in the `Content-Type` HTTP header.
    /// 4.
    /// InputStream + data 长度 + 文件名 + mine 类型, 封装mime 为httpheaders 调用5
    public func append(_ stream: InputStream,
                       withLength length: UInt64,
                       name: String,
                       fileName: String,
                       mimeType: String) {
        // 头
        let headers = contentHeaders(withName: name, fileName: fileName, mimeType: mimeType)
        // 调用方法5
        append(stream, withLength: length, headers: headers)
    }

    /// Creates a body part with the stream, length, and headers and appends it to the instance.
    ///
    /// The body part data will be encoded using the following format:
    ///
    /// - HTTP headers
    /// - Encoded stream data
    /// - Multipart form boundary
    ///
    /// - Parameters:
    ///   - stream:  `InputStream` to encode into the instance.
    ///   - length:  Length, in bytes, of the stream.
    ///   - headers: `HTTPHeaders` for the body part.
    /// 5.
    /// InputStream + data 长度 + HTTPHeaders
    public func append(_ stream: InputStream, withLength length: UInt64, headers: HTTPHeaders) {
        // 封装bodypart 对象
        let bodyPart = BodyPart(headers: headers, bodyStream: stream, bodyContentLength: length)
        // 存入数组
        bodyParts.append(bodyPart)
    }

    // MARK: - Data Encoding
    // 编码BodyPart 对象
    /// Encodes all appended body parts into a single `Data` value.
    ///
    /// - Note: This method will load all the appended body parts into memory all at the same time. This method should
    ///         only be used when the encoded data will have a small memory footprint. For large data cases, please use
    ///         the `writeEncodedData(to:))` method.
    ///
    /// - Returns: The encoded `Data`, if encoding is successful.
    /// - Throws:  An `AFError` if encoding encounters an error.
    /// 1. 编码为data 存在内存
    public func encode() throws -> Data {
        // 是否有错误
        if let bodyPartError = bodyPartError {
            throw bodyPartError
        }
        // 准备追加数据
        var encoded = Data()
        // 设置头尾分隔符
        bodyParts.first?.hasInitialBoundary = true
        bodyParts.last?.hasFinalBoundary = true
        // 遍历编码data, 追加
        for bodyPart in bodyParts {
            let encodedData = try encode(bodyPart)
            encoded.append(encodedData)
        }

        return encoded
    }

    /// Writes all appended body parts to the given file `URL`.
    ///
    /// This process is facilitated by reading and writing with input and output streams, respectively. Thus,
    /// this approach is very memory efficient and should be used for large body part data.
    ///
    /// - Parameter fileURL: File `URL` to which to write the form data.
    /// - Throws:            An `AFError` if encoding encounters an error.
    /// 2.
    /// 使用IOStream 往文件写数据, 适合处理大文件
    public func writeEncodedData(to fileURL: URL) throws {
        if let bodyPartError = bodyPartError {
            throw bodyPartError
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            // 文件已存在抛出错误
            throw AFError.multipartEncodingFailed(reason: .outputStreamFileAlreadyExists(at: fileURL))
        } else if !fileURL.isFileURL {
            // url 不是文件url 抛出错误
            throw AFError.multipartEncodingFailed(reason: .outputStreamURLInvalid(url: fileURL))
        }

        guard let outputStream = OutputStream(url: fileURL, append: false) else {
            // 创建OutputStream 失败抛出错误
            throw AFError.multipartEncodingFailed(reason: .outputStreamCreationFailed(for: fileURL))
        }

        outputStream.open()
        defer { outputStream.close() }
        // 设置头尾分隔符标志
        bodyParts.first?.hasInitialBoundary = true
        bodyParts.last?.hasFinalBoundary = true
        // 遍历使用私有方法写数据
        for bodyPart in bodyParts {
            try write(bodyPart, to: outputStream)
        }
    }

    // MARK: - Private - Body Part Encoding
    // 编码单个BodyPart 数据
    private func encode(_ bodyPart: BodyPart) throws -> Data {
        // 准备追加用的data
        var encoded = Data()
        // 先编码分隔符(要么是起始分隔符, 要么是中间分隔符)
        let initialData = bodyPart.hasInitialBoundary ? initialBoundaryData() : encapsulatedBoundaryData()
        encoded.append(initialData)
        // 编码表单头
        let headerData = encodeHeaders(for: bodyPart)
        encoded.append(headerData)
        // 编码表单数据
        let bodyStreamData = try encodeBodyStream(for: bodyPart)
        encoded.append(bodyStreamData)
        // 如果是最后一个表单数据了, 把结束分隔符编码进去
        if bodyPart.hasFinalBoundary {
            encoded.append(finalBoundaryData())
        }

        return encoded
    }
    // 编码表单头
    private func encodeHeaders(for bodyPart: BodyPart) -> Data {
        // 格式为: `表单头1名字: 表单头1值\r\n表单头2名字: 表单头2值\r\n...\r\n`
        let headerText = bodyPart.headers.map { "\($0.name): \($0.value)\(EncodingCharacters.crlf)" }
            .joined()
            + EncodingCharacters.crlf

        return Data(headerText.utf8)
    }
    // 编码表单数据
    private func encodeBodyStream(for bodyPart: BodyPart) throws -> Data {
        let inputStream = bodyPart.bodyStream
        // 打开stream
        inputStream.open()
        defer { inputStream.close() }

        var encoded = Data()
        // 直接循环读取
        while inputStream.hasBytesAvailable {
            // buffer, 长度为1024Byte
            var buffer = [UInt8](repeating: 0, count: streamBufferSize)
            // 一次读取一个1024Byte 的数据
            let bytesRead = inputStream.read(&buffer, maxLength: streamBufferSize)

            if let error = inputStream.streamError {
                throw AFError.multipartEncodingFailed(reason: .inputStreamReadFailed(error: error))
            }
            // 读到数据就追加, 否则跳出循环
            if bytesRead > 0 {
                encoded.append(buffer, count: bytesRead)
            } else {
                break
            }
        }

        guard UInt64(encoded.count) == bodyPart.bodyContentLength else {
            let error = AFError.UnexpectedInputStreamLength(bytesExpected: bodyPart.bodyContentLength,
                                                            bytesRead: UInt64(encoded.count))
            throw AFError.multipartEncodingFailed(reason: .inputStreamReadFailed(error: error))
        }

        return encoded
    }

    // MARK: - Private - Writing Body Part to Output Stream

    private func write(_ bodyPart: BodyPart, to outputStream: OutputStream) throws {
        // 编码数据前部分隔符(可能为起始分隔符, 也可能为中间分隔符)
        try writeInitialBoundaryData(for: bodyPart, to: outputStream)
        // 编码表单头
        try writeHeaderData(for: bodyPart, to: outputStream)
        // 编码表单数据
        try writeBodyStream(for: bodyPart, to: outputStream)
        // 编码结束分隔符(只有最后一个数据才会编码)
        try writeFinalBoundaryData(for: bodyPart, to: outputStream)
    }
    // 编码数据前部分隔符
    private func writeInitialBoundaryData(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        // 起始分隔符类型(可能为起始分隔符, 也可能为中间分隔符) 编码成Data
        let initialData = bodyPart.hasInitialBoundary ? initialBoundaryData() : encapsulatedBoundaryData()
        return try write(initialData, to: outputStream)
    }
    // 编码表单头
    private func writeHeaderData(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        // 把表单头编码成Data
        let headerData = encodeHeaders(for: bodyPart)
        return try write(headerData, to: outputStream)
    }
    // 编码表单数据
    private func writeBodyStream(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        let inputStream = bodyPart.bodyStream

        inputStream.open()
        defer { inputStream.close() }
        // 循环读取Bytes
        while inputStream.hasBytesAvailable {
            // 缓存, 大小为1024Byte
            var buffer = [UInt8](repeating: 0, count: streamBufferSize)
            let bytesRead = inputStream.read(&buffer, maxLength: streamBufferSize)

            if let streamError = inputStream.streamError {
                throw AFError.multipartEncodingFailed(reason: .inputStreamReadFailed(error: streamError))
            }

            if bytesRead > 0 {
                // 若读出来的数据小于缓存, 取前面有效数据
                // 上面转成Data不用这样处理是因为不需要往文件里写
                if buffer.count != bytesRead {
                    buffer = Array(buffer[0..<bytesRead])
                }

                try write(&buffer, to: outputStream)
            } else {
                break
            }
        }
    }
    // 编码最终分隔符
    private func writeFinalBoundaryData(for bodyPart: BodyPart, to outputStream: OutputStream) throws {
        if bodyPart.hasFinalBoundary {
            // 只有最后一个表单数据才编码最终分隔符
            return try write(finalBoundaryData(), to: outputStream)
        }
    }

    // MARK: - Private - Writing Buffered Data to Output Stream
    // 以Data 格式写入OStream
    private func write(_ data: Data, to outputStream: OutputStream) throws {
        // 拷贝成字节数组
        var buffer = [UInt8](repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)

        return try write(&buffer, to: outputStream)
    }
    // 以字节数组格式写入OStream
    private func write(_ buffer: inout [UInt8], to outputStream: OutputStream) throws {
        var bytesToWrite = buffer.count
        // 循环往OStream 中写数据
        while bytesToWrite > 0, outputStream.hasSpaceAvailable {
            // 写数据, 记录写了的字节数
            let bytesWritten = outputStream.write(buffer, maxLength: bytesToWrite)

            if let error = outputStream.streamError {
                throw AFError.multipartEncodingFailed(reason: .outputStreamWriteFailed(error: error))
            }
            // 减去写入的数据
            bytesToWrite -= bytesWritten
            // buffer 除去写入的数据
            if bytesToWrite > 0 {
                buffer = Array(buffer[bytesWritten..<buffer.count])
            }
        }
    }

    // MARK: - Private - Content Headers

    private func contentHeaders(withName name: String, fileName: String? = nil, mimeType: String? = nil) -> HTTPHeaders {
        var disposition = "form-data; name=\"\(name)\""
        if let fileName = fileName { disposition += "; filename=\"\(fileName)\"" }

        var headers: HTTPHeaders = [.contentDisposition(disposition)]
        if let mimeType = mimeType { headers.add(.contentType(mimeType)) }

        return headers
    }

    // MARK: - Private - Boundary Encoding

    private func initialBoundaryData() -> Data {
        BoundaryGenerator.boundaryData(forBoundaryType: .initial, boundary: boundary)
    }

    private func encapsulatedBoundaryData() -> Data {
        BoundaryGenerator.boundaryData(forBoundaryType: .encapsulated, boundary: boundary)
    }

    private func finalBoundaryData() -> Data {
        BoundaryGenerator.boundaryData(forBoundaryType: .final, boundary: boundary)
    }

    // MARK: - Private - Errors

    private func setBodyPartError(withReason reason: AFError.MultipartEncodingFailureReason) {
        guard bodyPartError == nil else { return }
        bodyPartError = AFError.multipartEncodingFailed(reason: reason)
    }
}

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers

extension MultipartFormData {
    // MARK: - Private - Mime Type

    private func mimeType(forPathExtension pathExtension: String) -> String {
        if #available(iOS 14, macOS 11, tvOS 14, watchOS 7, *) {
            return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        } else {
            if
                let id = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)?.takeRetainedValue(),
                let contentType = UTTypeCopyPreferredTagWithClass(id, kUTTagClassMIMEType)?.takeRetainedValue() {
                return contentType as String
            }

            return "application/octet-stream"
        }
    }
}

#else

extension MultipartFormData {
    // MARK: - Private - Mime Type

    private func mimeType(forPathExtension pathExtension: String) -> String {
        #if !(os(Linux) || os(Windows))
        if
            let id = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)?.takeRetainedValue(),
            let contentType = UTTypeCopyPreferredTagWithClass(id, kUTTagClassMIMEType)?.takeRetainedValue() {
            return contentType as String
        }
        #endif

        return "application/octet-stream"
    }
}

#endif
