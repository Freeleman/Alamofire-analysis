//
//  Validation.swift
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

extension Request {
    // MARK: Helper Types

    fileprivate typealias ErrorReason = AFError.ResponseValidationFailureReason

    /// Used to represent whether a validation succeeded or failed.
    public typealias ValidationResult = Result<Void, Error>
    // MIME 类型结构体 "image/jpeg"
    fileprivate struct MIMEType {
        let type: String
        let subtype: String
        // 是否是通配类型的MIME
        var isWildcard: Bool { type == "*" && subtype == "*" }
        // 从string 格式初始化, 失败返回nil
        init?(_ string: String) {
            let components: [String] = {
                let stripped = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let split = stripped[..<(stripped.range(of: ";")?.lowerBound ?? stripped.endIndex)]

                return split.components(separatedBy: "/")
            }()

            if let type = components.first, let subtype = components.last {
                self.type = type
                self.subtype = subtype
            } else {
                return nil
            }
        }
        // 校验MIME
        func matches(_ mime: MIMEType) -> Bool {
            switch (type, subtype) {
            case (mime.type, mime.subtype), (mime.type, "*"), ("*", mime.subtype), ("*", "*"):
                return true
            default:
                return false
            }
        }
    }

    // MARK: Properties
    // 默认允许的响应状态码 2xx - 3xx
    fileprivate var acceptableStatusCodes: Range<Int> { 200..<300 }
    // 默认允许的ContentType, 会从请求头中的Accept 字段取值
    fileprivate var acceptableContentTypes: [String] {
        if let accept = request?.value(forHTTPHeaderField: "Accept") {
            return accept.components(separatedBy: ",")
        }

        return ["*/*"]
    }

    // MARK: Status Code
    // 校验响应的状态码是否与在传入的状态码集合中
    fileprivate func validate<S: Sequence>(statusCode acceptableStatusCodes: S,
                                           response: HTTPURLResponse)
        -> ValidationResult
        where S.Iterator.Element == Int {
            // 如果支持的状态码中包含响应的状态码, 返回成功, 否则返回对应错误
        if acceptableStatusCodes.contains(response.statusCode) {
            return .success(())
        } else {
            let reason: ErrorReason = .unacceptableStatusCode(code: response.statusCode)
            return .failure(AFError.responseValidationFailed(reason: reason))
        }
    }

    // MARK: Content Type
    // 校验响应的contentType 是否在传入的contentType 集合中
    // 入参有个Data, 如果data 为nil, 那就直接认为contentType 类型符合
    fileprivate func validate<S: Sequence>(contentType acceptableContentTypes: S,
                                           response: HTTPURLResponse,
                                           data: Data?)
        -> ValidationResult
        where S.Iterator.Element == String {
        guard let data = data, !data.isEmpty else { return .success(()) }

        return validate(contentType: acceptableContentTypes, response: response)
    }
    // 校验响应的contentType 是否在传入的contentType 集合中
    fileprivate func validate<S: Sequence>(contentType acceptableContentTypes: S,
                                           response: HTTPURLResponse)
        -> ValidationResult
    
        where S.Iterator.Element == String {
            // 先获取响应的MIME类型
        guard
            let responseContentType = response.mimeType,
            let responseMIMEType = MIMEType(responseContentType)
        else {
            // 获取响应的MIME 类型失败, 检测下允许的ContentType 是不是通配类型
            for contentType in acceptableContentTypes {
                if let mimeType = MIMEType(contentType), mimeType.isWildcard {
                    return .success(())
                }
            }

            let error: AFError = {
                // 未能获取到响应的MIME, 且请求的ContentType 不是通配的
                let reason: ErrorReason = .missingContentType(acceptableContentTypes: acceptableContentTypes.sorted())
                return AFError.responseValidationFailed(reason: reason)
            }()

            return .failure(error)
        }
            // 获取到MIME, 开始校验
        for contentType in acceptableContentTypes {
            if let acceptableMIMEType = MIMEType(contentType), acceptableMIMEType.matches(responseMIMEType) {
                return .success(())
            }
        }

        let error: AFError = {
            let reason: ErrorReason = .unacceptableContentType(acceptableContentTypes: acceptableContentTypes.sorted(),
                                                               responseContentType: responseContentType)

            return AFError.responseValidationFailed(reason: reason)
        }()

        return .failure(error)
    }
}

// MARK: -

extension DataRequest {
    /// A closure used to validate a request that takes a URL request, a URL response and data, and returns whether the
    /// request was valid.
    public typealias Validation = (URLRequest?, HTTPURLResponse, Data?) -> ValidationResult

    /// Validates that the response has a status code in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter acceptableStatusCodes: `Sequence` of acceptable response status codes.
    ///
    /// - Returns:                         The instance.
    /// 指定状态码校验
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int {
        validate { [unowned self] _, response, _ in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    /// Validates that the response has a content type in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - parameter contentType: The acceptable content types, which may specify wildcard types and/or subtypes.
    ///
    /// - returns: The request.
    /// 指定contentType 校验
    /// 注意contentType 是自动闭包
    /// 把执行获取contentType 的时机推迟到了要执行校验的时候调用
    /// 这样如果在请求完成前, 取消了请求, 就可以不用获取比较的contentType, 节省资源
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @autoclosure () -> S) -> Self where S.Iterator.Element == String {
        validate { [unowned self] _, response, data in
            self.validate(contentType: acceptableContentTypes(), response: response, data: data)
        }
    }

    /// Validates that the response has a status code in the default acceptable range of 200...299, and that the content
    /// type matches any specified in the Accept HTTP header field.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - returns: The request.
    /// 使用默认的状态码与contentType
    @discardableResult
    public func validate() -> Self {
        let contentTypes: () -> [String] = { [unowned self] in
            self.acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}

extension DataStreamRequest {
    /// A closure used to validate a request that takes a `URLRequest` and `HTTPURLResponse` and returns whether the
    /// request was valid.
    public typealias Validation = (_ request: URLRequest?, _ response: HTTPURLResponse) -> ValidationResult

    /// Validates that the response has a status code in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter acceptableStatusCodes: `Sequence` of acceptable response status codes.
    ///
    /// - Returns:                         The instance.
    ///
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int {
        validate { [unowned self] _, response in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    /// Validates that the response has a content type in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - parameter contentType: The acceptable content types, which may specify wildcard types and/or subtypes.
    ///
    /// - returns: The request.
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @autoclosure () -> S) -> Self where S.Iterator.Element == String {
        validate { [unowned self] _, response in
            self.validate(contentType: acceptableContentTypes(), response: response)
        }
    }

    /// Validates that the response has a status code in the default acceptable range of 200...299, and that the content
    /// type matches any specified in the Accept HTTP header field.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Returns: The instance.
    @discardableResult
    public func validate() -> Self {
        let contentTypes: () -> [String] = { [unowned self] in
            self.acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}

// MARK: -

extension DownloadRequest {
    /// A closure used to validate a request that takes a URL request, a URL response, a temporary URL and a
    /// destination URL, and returns whether the request was valid.
    public typealias Validation = (_ request: URLRequest?,
                                   _ response: HTTPURLResponse,
                                   _ fileURL: URL?)
        -> ValidationResult

    /// Validates that the response has a status code in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter acceptableStatusCodes: `Sequence` of acceptable response status codes.
    ///
    /// - Returns:                         The instance.
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int {
        validate { [unowned self] _, response, _ in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    /// Validates that the response has a content type in the specified sequence.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - parameter contentType: The acceptable content types, which may specify wildcard types and/or subtypes.
    ///
    /// - returns: The request.
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @autoclosure () -> S) -> Self where S.Iterator.Element == String {
        validate { [unowned self] _, response, fileURL in
            guard let validFileURL = fileURL else {
                return .failure(AFError.responseValidationFailed(reason: .dataFileNil))
            }

            do {
                let data = try Data(contentsOf: validFileURL)
                return self.validate(contentType: acceptableContentTypes(), response: response, data: data)
            } catch {
                return .failure(AFError.responseValidationFailed(reason: .dataFileReadFailed(at: validFileURL)))
            }
        }
    }

    /// Validates that the response has a status code in the default acceptable range of 200...299, and that the content
    /// type matches any specified in the Accept HTTP header field.
    ///
    /// If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - returns: The request.
    @discardableResult
    public func validate() -> Self {
        let contentTypes = { [unowned self] in
            self.acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}
