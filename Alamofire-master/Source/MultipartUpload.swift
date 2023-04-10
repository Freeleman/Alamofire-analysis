//
//  MultipartUpload.swift
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

/// Internal type which encapsulates a `MultipartFormData` upload.
final class MultipartUpload {
    // 懒加载属性result, 首次读取时会调用build 方法编码MultipartFormData 数据
    lazy var result = Result { try build() }

    @Protected
    private(set) var multipartFormData: MultipartFormData
    let encodingMemoryThreshold: UInt64
    let request: URLRequestConvertible
    let fileManager: FileManager

    init(encodingMemoryThreshold: UInt64,
         request: URLRequestConvertible,
         multipartFormData: MultipartFormData) {
        self.encodingMemoryThreshold = encodingMemoryThreshold
        self.request = request
        fileManager = multipartFormData.fileManager
        self.multipartFormData = multipartFormData
    }
    // 编码数据, 并返回创建的URLRequest 与UploadRequest.Uploadable 关联的元组
    func build() throws -> UploadRequest.Uploadable {
        // 编码后的Uploadable
        let uploadable: UploadRequest.Uploadable
        if $multipartFormData.contentLength < encodingMemoryThreshold {
            // 表单数据小于设置的内存开销
            let data = try $multipartFormData.read { try $0.encode() }

            uploadable = .data(data)
        } else {
            // 系统缓存目录
            let tempDirectoryURL = fileManager.temporaryDirectory
            // 保存临时表单文件的目录
            let directoryURL = tempDirectoryURL.appendingPathComponent("org.alamofire.manager/multipart.form.data")
            // 临时文件名
            let fileName = UUID().uuidString
            // 临时文件url
            let fileURL = directoryURL.appendingPathComponent(fileName)
            // 创建临时表单文件目录
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

            do {
                // 把表单数据编码到临时文件
                try $multipartFormData.read { try $0.writeEncodedData(to: fileURL) }
            } catch {
                // Cleanup after attempted write if it fails.
                try? fileManager.removeItem(at: fileURL)
                throw error
            }
            // 返回的UploadRequest.Uploadable, 并设置需要完成后删除临时文件
            uploadable = .file(fileURL, shouldRemove: true)
        }

        return uploadable
    }
}

extension MultipartUpload: UploadConvertible {
    func asURLRequest() throws -> URLRequest {
        var urlRequest = try request.asURLRequest()

        $multipartFormData.read { multipartFormData in
            urlRequest.headers.add(.contentType(multipartFormData.contentType))
        }

        return urlRequest
    }

    func createUploadable() throws -> UploadRequest.Uploadable {
        try result.get()
    }
}
