//
//  AFError.swift
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

/// `AFError` is the error type returned by Alamofire. It encompasses a few different types of errors, each with
/// their own associated reasons.
/// 大部分为带参数类型
public enum AFError: Error {
    /// The underlying reason the `.multipartEncodingFailed` error occurred.
    /// 多表单编码失败具体原因
    public enum MultipartEncodingFailureReason {
        /// The `fileURL` provided for reading an encodable body part isn't a file `URL`.
        case bodyPartURLInvalid(url: URL)
        /// The filename of the `fileURL` provided has either an empty `lastPathComponent` or `pathExtension.
        case bodyPartFilenameInvalid(in: URL)
        /// The file at the `fileURL` provided was not reachable.
        case bodyPartFileNotReachable(at: URL)
        /// Attempting to check the reachability of the `fileURL` provided threw an error.
        case bodyPartFileNotReachableWithError(atURL: URL, error: Error)
        /// The file at the `fileURL` provided is actually a directory.
        case bodyPartFileIsDirectory(at: URL)
        /// The size of the file at the `fileURL` provided was not returned by the system.
        case bodyPartFileSizeNotAvailable(at: URL)
        /// The attempt to find the size of the file at the `fileURL` provided threw an error.
        case bodyPartFileSizeQueryFailedWithError(forURL: URL, error: Error)
        /// An `InputStream` could not be created for the provided `fileURL`.
        case bodyPartInputStreamCreationFailed(for: URL)
        /// An `OutputStream` could not be created when attempting to write the encoded data to disk.
        case outputStreamCreationFailed(for: URL)
        /// The encoded body data could not be written to disk because a file already exists at the provided `fileURL`.
        case outputStreamFileAlreadyExists(at: URL)
        /// The `fileURL` provided for writing the encoded body data to disk is not a file `URL`.
        case outputStreamURLInvalid(url: URL)
        /// The attempt to write the encoded body data to disk failed with an underlying error.
        case outputStreamWriteFailed(error: Error)
        /// The attempt to read an encoded body part `InputStream` failed with underlying system error.
        case inputStreamReadFailed(error: Error)
    }

    /// Represents unexpected input stream length that occur when encoding the `MultipartFormData`. Instances will be
    /// embedded within an `AFError.multipartEncodingFailed` `.inputStreamReadFailed` case.
    public struct UnexpectedInputStreamLength: Error {
        /// The expected byte count to read.
        public var bytesExpected: UInt64
        /// The actual byte count read.
        public var bytesRead: UInt64
    }

    /// The underlying reason the `.parameterEncodingFailed` error occurred.
    /// 定义请求参数使用ParameterEncoding 协议对象编码失败时的原因, 扩展枚举用来快速获取潜在Error 参数
    public enum ParameterEncodingFailureReason {
        /// The `URLRequest` did not have a `URL` to encode.
        case missingURL
        /// JSON serialization failed with an underlying system error during the encoding process.
        case jsonEncodingFailed(error: Error)
        /// Custom parameter encoding failed due to the associated `Error`.
        case customEncodingFailed(error: Error)
    }

    /// The underlying reason the `.parameterEncoderFailed` error occurred.
    /// 定义请求参数使用ParameterEncoder 协议对象编码失败时的原因, 扩展枚举用来快速获取潜在Error 参数
    public enum ParameterEncoderFailureReason {
        /// Possible missing components.
        public enum RequiredComponent {
            /// The `URL` was missing or unable to be extracted from the passed `URLRequest` or during encoding.
            case url
            /// The `HTTPMethod` could not be extracted from the passed `URLRequest`.
            case httpMethod(rawValue: String)
        }

        /// A `RequiredComponent` was missing during encoding.
        case missingRequiredComponent(RequiredComponent)
        /// The underlying encoder failed with the associated error.
        case encoderFailed(error: Error)
    }

    /// The underlying reason the `.responseValidationFailed` error occurred.
    /// 定义了响应数据的有效性检测失败的具体原因
    public enum ResponseValidationFailureReason {
        /// The data file containing the server response did not exist.
        case dataFileNil
        /// The data file containing the server response at the associated `URL` could not be read.
        case dataFileReadFailed(at: URL)
        /// The response did not contain a `Content-Type` and the `acceptableContentTypes` provided did not contain a
        /// wildcard type.
        case missingContentType(acceptableContentTypes: [String])
        /// The response `Content-Type` did not match any type in the provided `acceptableContentTypes`.
        case unacceptableContentType(acceptableContentTypes: [String], responseContentType: String)
        /// The response status code was not acceptable.
        case unacceptableStatusCode(code: Int)
        /// Custom response validation failed due to the associated `Error`.
        case customValidationFailed(error: Error)
    }

    /// The underlying reason the response serialization error occurred.
    /// 响应序列化失败, string, json, decodable, 或者用户自定义类型失败的原因
    public enum ResponseSerializationFailureReason {
        /// The server response contained no data or the data was zero length.
        case inputDataNilOrZeroLength
        /// The file containing the server response did not exist.
        case inputFileNil
        /// The file containing the server response could not be read from the associated `URL`.
        case inputFileReadFailed(at: URL)
        /// String serialization failed using the provided `String.Encoding`.
        case stringSerializationFailed(encoding: String.Encoding)
        /// JSON serialization failed with an underlying system error.
        case jsonSerializationFailed(error: Error)
        /// A `DataDecoder` failed to decode the response due to the associated `Error`.
        case decodingFailed(error: Error)
        /// A custom response serializer failed due to the associated `Error`.
        case customSerializationFailed(error: Error)
        /// Generic serialization failed for an empty response that wasn't type `Empty` but instead the associated type.
        case invalidEmptyResponse(type: String)
    }

    #if !(os(Linux) || os(Windows))
    /// Underlying reason a server trust evaluation error occurred.
    public enum ServerTrustFailureReason {
        /// The output of a server trust evaluation.
        public struct Output {
            /// The host for which the evaluation was performed.
            public let host: String
            /// The `SecTrust` value which was evaluated.
            public let trust: SecTrust
            /// The `OSStatus` of evaluation operation.
            public let status: OSStatus
            /// The result of the evaluation operation.
            public let result: SecTrustResultType

            /// Creates an `Output` value from the provided values.
            init(_ host: String, _ trust: SecTrust, _ status: OSStatus, _ result: SecTrustResultType) {
                self.host = host
                self.trust = trust
                self.status = status
                self.result = result
            }
        }

        /// No `ServerTrustEvaluator` was found for the associated host.
        case noRequiredEvaluator(host: String)
        /// No certificates were found with which to perform the trust evaluation.
        case noCertificatesFound
        /// No public keys were found with which to perform the trust evaluation.
        case noPublicKeysFound
        /// During evaluation, application of the associated `SecPolicy` failed.
        case policyApplicationFailed(trust: SecTrust, policy: SecPolicy, status: OSStatus)
        /// During evaluation, setting the associated anchor certificates failed.
        case settingAnchorCertificatesFailed(status: OSStatus, certificates: [SecCertificate])
        /// During evaluation, creation of the revocation policy failed.
        case revocationPolicyCreationFailed
        /// `SecTrust` evaluation failed with the associated `Error`, if one was produced.
        case trustEvaluationFailed(error: Error?)
        /// Default evaluation failed with the associated `Output`.
        case defaultEvaluationFailed(output: Output)
        /// Host validation failed with the associated `Output`.
        case hostValidationFailed(output: Output)
        /// Revocation check failed with the associated `Output` and options.
        case revocationCheckFailed(output: Output, options: RevocationTrustEvaluator.Options)
        /// Certificate pinning failed.
        case certificatePinningFailed(host: String, trust: SecTrust, pinnedCertificates: [SecCertificate], serverCertificates: [SecCertificate])
        /// Public key pinning failed.
        case publicKeyPinningFailed(host: String, trust: SecTrust, pinnedKeys: [SecKey], serverKeys: [SecKey])
        /// Custom server trust evaluation failed due to the associated `Error`.
        case customEvaluationFailed(error: Error)
    }
    #endif

    /// The underlying reason the `.urlRequestValidationFailed`
    /// 请求检测失败, get 请求带了body 参数, 抛出该错误, body 的data 数据返回
    public enum URLRequestValidationFailureReason {
        /// URLRequest with GET method had body data.
        case bodyDataInGETRequest(Data)
    }

    ///  `UploadableConvertible` threw an error in `createUploadable()`.
    ///  上传请求, 调用createUploadable() 方法穿件Uploadable 的时候失败, 枚举参数为错误原因
    case createUploadableFailed(error: Error)
    ///  `URLRequestConvertible` threw an error in `asURLRequest()`.
    /// URLRequestConvertible 秀恶意对象调用asURLRequest() 方法创建URLRequest 对象时失败, 参数为错误原因
    case createURLRequestFailed(error: Error)
    /// `SessionDelegate` threw an error while attempting to move downloaded file to destination URL.
    /// SessionDelegate 处理下载请求时, 试图把下载文件从临时路径移动到目标路径时失败, 参数为错误原因, 源路径, 目标路径
    case downloadedFileMoveFailed(error: Error, source: URL, destination: URL)
    /// `Request` was explicitly cancelled.
    /// 请求取消
    case explicitlyCancelled
    /// `URLConvertible` type failed to create a valid `URL`.
    /// URLConvertible 对象调用asURL() 方法创建URL 对象失败
    case invalidURL(url: URLConvertible)
    /// Multipart form encoding failed.
    /// 多表单餐护士编码失败, 参数为编码失败具体原因, 是定义的枚举类型
    case multipartEncodingFailed(reason: MultipartEncodingFailureReason)
    /// `ParameterEncoding` threw an error during the encoding process.
    /// 请求测试使用ParameterEncoding 编码失败, 具体原因, 定义的枚举类型
    case parameterEncodingFailed(reason: ParameterEncodingFailureReason)
    /// `ParameterEncoder` threw an error while running the encoder.
    /// 请求测试使用ParameterEncoder 编码失败, 具体原因, 定义的枚举类型
    case parameterEncoderFailed(reason: ParameterEncoderFailureReason)
    /// `RequestAdapter` threw an error during adaptation.
    /// RequestAdapter 请求适配器在预处理请求时出错, 具体原因
    case requestAdaptationFailed(error: Error)
    /// `RequestRetrier` threw an error during the request retry process.
    /// RequestRetrier 请求重试器在处理请求行为时出错, 抛出异常, 重试出错, 请求失败原始原因
    case requestRetryFailed(retryError: Error, originalError: Error)
    /// Response validation failed.
    /// 若定义了响应有效性校验, 微能通过校验时抛出该错误, 未能通过校验具体原因
    case responseValidationFailed(reason: ResponseValidationFailureReason)
    /// Response serialization failed.
    /// 响应数据序列化出错, 具体原因
    case responseSerializationFailed(reason: ResponseSerializationFailureReason)
    #if !(os(Linux) || os(Windows))
    /// `ServerTrustEvaluating` instance threw an error during trust evaluation.
    case serverTrustEvaluationFailed(reason: ServerTrustFailureReason)
    #endif
    /// `Session` which issued the `Request` was deinitialized, most likely because its reference went out of scope.
    /// 请求还没落地, session 释放, 抛出错误
    case sessionDeinitialized
    /// `Session` was explicitly invalidated, possibly with the `Error` produced by the underlying `URLSession`.
    /// URLSession 出错, 带上URLSession 出错原因
    case sessionInvalidated(error: Error?)
    /// `URLSessionTask` completed with error.
    /// URLSessionTask 出错
    case sessionTaskFailed(error: Error)
    /// `URLRequest` failed validation.
    /// URLRequest 有效性校验出错, 只有一个错误可能, get 请求, 带有body 数据
    case urlRequestValidationFailed(reason: URLRequestValidationFailureReason)
}

// 快速转换成AFError 类型的方法
extension Error {
    /// Returns the instance cast as an `AFError`.
    /// 返回可选类型的AFError, 若self 是 AFError类型, 返回可选对象, 否则返回nil
    public var asAFError: AFError? {
        self as? AFError
    }

    /// Returns the instance cast as an `AFError`. If casting fails, a `fatalError` with the specified `message` is thrown.
    /// 返回不可选的AFError 若self 不是AFError 类型, 使用参数抛出异常, message 自动闭包
    public func asAFError(orFailWith message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) -> AFError {
        guard let afError = self as? AFError else {
            fatalError(message(), file: file, line: line)
        }
        return afError
    }

    /// Casts the instance as `AFError` or returns `defaultAFError`
    /// 返回不可选AFError 对象, 若self 不是AFError 类型, 就会使用参数自动闭包来创建一个默认的AFError
    func asAFError(or defaultAFError: @autoclosure () -> AFError) -> AFError {
        self as? AFError ?? defaultAFError()
    }
}

// MARK: - Error Booleans

extension AFError {
    /// Returns whether the instance is `.sessionDeinitialized`.
    public var isSessionDeinitializedError: Bool {
        if case .sessionDeinitialized = self { return true }
        return false
    }

    /// Returns whether the instance is `.sessionInvalidated`.
    public var isSessionInvalidatedError: Bool {
        if case .sessionInvalidated = self { return true }
        return false
    }

    /// Returns whether the instance is `.explicitlyCancelled`.
    public var isExplicitlyCancelledError: Bool {
        if case .explicitlyCancelled = self { return true }
        return false
    }

    /// Returns whether the instance is `.invalidURL`.
    public var isInvalidURLError: Bool {
        if case .invalidURL = self { return true }
        return false
    }

    /// Returns whether the instance is `.parameterEncodingFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isParameterEncodingError: Bool {
        if case .parameterEncodingFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `.parameterEncoderFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isParameterEncoderError: Bool {
        if case .parameterEncoderFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `.multipartEncodingFailed`. When `true`, the `url` and `underlyingError`
    /// properties will contain the associated values.
    public var isMultipartEncodingError: Bool {
        if case .multipartEncodingFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `.requestAdaptationFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isRequestAdaptationError: Bool {
        if case .requestAdaptationFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `.responseValidationFailed`. When `true`, the `acceptableContentTypes`,
    /// `responseContentType`,  `responseCode`, and `underlyingError` properties will contain the associated values.
    public var isResponseValidationError: Bool {
        if case .responseValidationFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `.responseSerializationFailed`. When `true`, the `failedStringEncoding` and
    /// `underlyingError` properties will contain the associated values.
    public var isResponseSerializationError: Bool {
        if case .responseSerializationFailed = self { return true }
        return false
    }

    #if !(os(Linux) || os(Windows))
    /// Returns whether the instance is `.serverTrustEvaluationFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isServerTrustEvaluationError: Bool {
        if case .serverTrustEvaluationFailed = self { return true }
        return false
    }
    #endif

    /// Returns whether the instance is `requestRetryFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isRequestRetryError: Bool {
        if case .requestRetryFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `createUploadableFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isCreateUploadableError: Bool {
        if case .createUploadableFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `createURLRequestFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isCreateURLRequestError: Bool {
        if case .createURLRequestFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `downloadedFileMoveFailed`. When `true`, the `destination` and `underlyingError` properties will
    /// contain the associated values.
    public var isDownloadedFileMoveError: Bool {
        if case .downloadedFileMoveFailed = self { return true }
        return false
    }

    /// Returns whether the instance is `createURLRequestFailed`. When `true`, the `underlyingError` property will
    /// contain the associated value.
    public var isSessionTaskError: Bool {
        if case .sessionTaskFailed = self { return true }
        return false
    }
}

// MARK: - Convenience Properties

extension AFError {
    /// The `URLConvertible` associated with the error.
    public var urlConvertible: URLConvertible? {
        guard case let .invalidURL(url) = self else { return nil }
        return url
    }

    /// The `URL` associated with the error.
    public var url: URL? {
        guard case let .multipartEncodingFailed(reason) = self else { return nil }
        return reason.url
    }

    /// The underlying `Error` responsible for generating the failure associated with `.sessionInvalidated`,
    /// `.parameterEncodingFailed`, `.parameterEncoderFailed`, `.multipartEncodingFailed`, `.requestAdaptationFailed`,
    /// `.responseSerializationFailed`, `.requestRetryFailed` errors.
    public var underlyingError: Error? {
        switch self {
        case let .multipartEncodingFailed(reason):
            return reason.underlyingError
        case let .parameterEncodingFailed(reason):
            return reason.underlyingError
        case let .parameterEncoderFailed(reason):
            return reason.underlyingError
        case let .requestAdaptationFailed(error):
            return error
        case let .requestRetryFailed(retryError, _):
            return retryError
        case let .responseValidationFailed(reason):
            return reason.underlyingError
        case let .responseSerializationFailed(reason):
            return reason.underlyingError
        #if !(os(Linux) || os(Windows))
        case let .serverTrustEvaluationFailed(reason):
            return reason.underlyingError
        #endif
        case let .sessionInvalidated(error):
            return error
        case let .createUploadableFailed(error):
            return error
        case let .createURLRequestFailed(error):
            return error
        case let .downloadedFileMoveFailed(error, _, _):
            return error
        case let .sessionTaskFailed(error):
            return error
        case .explicitlyCancelled,
             .invalidURL,
             .sessionDeinitialized,
             .urlRequestValidationFailed:
            return nil
        }
    }

    /// The acceptable `Content-Type`s of a `.responseValidationFailed` error.
    public var acceptableContentTypes: [String]? {
        guard case let .responseValidationFailed(reason) = self else { return nil }
        return reason.acceptableContentTypes
    }

    /// The response `Content-Type` of a `.responseValidationFailed` error.
    public var responseContentType: String? {
        guard case let .responseValidationFailed(reason) = self else { return nil }
        return reason.responseContentType
    }

    /// The response code of a `.responseValidationFailed` error.
    public var responseCode: Int? {
        guard case let .responseValidationFailed(reason) = self else { return nil }
        return reason.responseCode
    }

    /// The `String.Encoding` associated with a failed `.stringResponse()` call.
    public var failedStringEncoding: String.Encoding? {
        guard case let .responseSerializationFailed(reason) = self else { return nil }
        return reason.failedStringEncoding
    }

    /// The `source` URL of a `.downloadedFileMoveFailed` error.
    public var sourceURL: URL? {
        guard case let .downloadedFileMoveFailed(_, source, _) = self else { return nil }
        return source
    }

    /// The `destination` URL of a `.downloadedFileMoveFailed` error.
    public var destinationURL: URL? {
        guard case let .downloadedFileMoveFailed(_, _, destination) = self else { return nil }
        return destination
    }

    #if !(os(Linux) || os(Windows))
    /// The download resume data of any underlying network error. Only produced by `DownloadRequest`s.
    public var downloadResumeData: Data? {
        (underlyingError as? URLError)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    }
    #endif
}

extension AFError.ParameterEncodingFailureReason {
    var underlyingError: Error? {
        switch self {
        case let .jsonEncodingFailed(error),
             let .customEncodingFailed(error):
            return error
        case .missingURL:
            return nil
        }
    }
}

extension AFError.ParameterEncoderFailureReason {
    var underlyingError: Error? {
        switch self {
        case let .encoderFailed(error):
            return error
        case .missingRequiredComponent:
            return nil
        }
    }
}
// 扩展MultipartEncodingFailureReason 添加可以快速获取请求url 与潜在Error 对象的计算属性
extension AFError.MultipartEncodingFailureReason {
    var url: URL? {
        switch self {
        case let .bodyPartURLInvalid(url),
             let .bodyPartFilenameInvalid(url),
             let .bodyPartFileNotReachable(url),
             let .bodyPartFileIsDirectory(url),
             let .bodyPartFileSizeNotAvailable(url),
             let .bodyPartInputStreamCreationFailed(url),
             let .outputStreamCreationFailed(url),
             let .outputStreamFileAlreadyExists(url),
             let .outputStreamURLInvalid(url),
             let .bodyPartFileNotReachableWithError(url, _),
             let .bodyPartFileSizeQueryFailedWithError(url, _):
            return url
        case .outputStreamWriteFailed,
             .inputStreamReadFailed:
            return nil
        }
    }

    var underlyingError: Error? {
        switch self {
        case let .bodyPartFileNotReachableWithError(_, error),
             let .bodyPartFileSizeQueryFailedWithError(_, error),
             let .outputStreamWriteFailed(error),
             let .inputStreamReadFailed(error):
            return error
        case .bodyPartURLInvalid,
             .bodyPartFilenameInvalid,
             .bodyPartFileNotReachable,
             .bodyPartFileIsDirectory,
             .bodyPartFileSizeNotAvailable,
             .bodyPartInputStreamCreationFailed,
             .outputStreamCreationFailed,
             .outputStreamFileAlreadyExists,
             .outputStreamURLInvalid:
            return nil
        }
    }
}

// 添加便捷计算属性, 快速获取请求接收的ContentType, 响应返回ContentType, 响应状态码, 潜在Error
extension AFError.ResponseValidationFailureReason {
    var acceptableContentTypes: [String]? {
        switch self {
        case let .missingContentType(types),
             let .unacceptableContentType(types, _):
            return types
        case .dataFileNil,
             .dataFileReadFailed,
             .unacceptableStatusCode,
             .customValidationFailed:
            return nil
        }
    }

    var responseContentType: String? {
        switch self {
        case let .unacceptableContentType(_, responseType):
            return responseType
        case .dataFileNil,
             .dataFileReadFailed,
             .missingContentType,
             .unacceptableStatusCode,
             .customValidationFailed:
            return nil
        }
    }

    var responseCode: Int? {
        switch self {
        case let .unacceptableStatusCode(code):
            return code
        case .dataFileNil,
             .dataFileReadFailed,
             .missingContentType,
             .unacceptableContentType,
             .customValidationFailed:
            return nil
        }
    }

    var underlyingError: Error? {
        switch self {
        case let .customValidationFailed(error):
            return error
        case .dataFileNil,
             .dataFileReadFailed,
             .missingContentType,
             .unacceptableContentType,
             .unacceptableStatusCode:
            return nil
        }
    }
}

// 序列化为string 出错时使用的字符串编码, 以及Error
extension AFError.ResponseSerializationFailureReason {
    var failedStringEncoding: String.Encoding? {
        switch self {
        case let .stringSerializationFailed(encoding):
            return encoding
        case .inputDataNilOrZeroLength,
             .inputFileNil,
             .inputFileReadFailed(_),
             .jsonSerializationFailed(_),
             .decodingFailed(_),
             .customSerializationFailed(_),
             .invalidEmptyResponse:
            return nil
        }
    }

    var underlyingError: Error? {
        switch self {
        case let .jsonSerializationFailed(error),
             let .decodingFailed(error),
             let .customSerializationFailed(error):
            return error
        case .inputDataNilOrZeroLength,
             .inputFileNil,
             .inputFileReadFailed,
             .stringSerializationFailed,
             .invalidEmptyResponse:
            return nil
        }
    }
}

#if !(os(Linux) || os(Windows))
extension AFError.ServerTrustFailureReason {
    var output: AFError.ServerTrustFailureReason.Output? {
        switch self {
        case let .defaultEvaluationFailed(output),
             let .hostValidationFailed(output),
             let .revocationCheckFailed(output, _):
            return output
        case .noRequiredEvaluator,
             .noCertificatesFound,
             .noPublicKeysFound,
             .policyApplicationFailed,
             .settingAnchorCertificatesFailed,
             .revocationPolicyCreationFailed,
             .trustEvaluationFailed,
             .certificatePinningFailed,
             .publicKeyPinningFailed,
             .customEvaluationFailed:
            return nil
        }
    }

    var underlyingError: Error? {
        switch self {
        case let .customEvaluationFailed(error):
            return error
        case let .trustEvaluationFailed(error):
            return error
        case .noRequiredEvaluator,
             .noCertificatesFound,
             .noPublicKeysFound,
             .policyApplicationFailed,
             .settingAnchorCertificatesFailed,
             .revocationPolicyCreationFailed,
             .defaultEvaluationFailed,
             .hostValidationFailed,
             .revocationCheckFailed,
             .certificatePinningFailed,
             .publicKeyPinningFailed:
            return nil
        }
    }
}
#endif

// MARK: - Error Descriptions

extension AFError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .explicitlyCancelled:
            return "Request explicitly cancelled."
        case let .invalidURL(url):
            return "URL is not valid: \(url)"
        case let .parameterEncodingFailed(reason):
            return reason.localizedDescription
        case let .parameterEncoderFailed(reason):
            return reason.localizedDescription
        case let .multipartEncodingFailed(reason):
            return reason.localizedDescription
        case let .requestAdaptationFailed(error):
            return "Request adaption failed with error: \(error.localizedDescription)"
        case let .responseValidationFailed(reason):
            return reason.localizedDescription
        case let .responseSerializationFailed(reason):
            return reason.localizedDescription
        case let .requestRetryFailed(retryError, originalError):
            return """
            Request retry failed with retry error: \(retryError.localizedDescription), \
            original error: \(originalError.localizedDescription)
            """
        case .sessionDeinitialized:
            return """
            Session was invalidated without error, so it was likely deinitialized unexpectedly. \
            Be sure to retain a reference to your Session for the duration of your requests.
            """
        case let .sessionInvalidated(error):
            return "Session was invalidated with error: \(error?.localizedDescription ?? "No description.")"
        #if !(os(Linux) || os(Windows))
        case let .serverTrustEvaluationFailed(reason):
            return "Server trust evaluation failed due to reason: \(reason.localizedDescription)"
        #endif
        case let .urlRequestValidationFailed(reason):
            return "URLRequest validation failed due to reason: \(reason.localizedDescription)"
        case let .createUploadableFailed(error):
            return "Uploadable creation failed with error: \(error.localizedDescription)"
        case let .createURLRequestFailed(error):
            return "URLRequest creation failed with error: \(error.localizedDescription)"
        case let .downloadedFileMoveFailed(error, source, destination):
            return "Moving downloaded file from: \(source) to: \(destination) failed with error: \(error.localizedDescription)"
        case let .sessionTaskFailed(error):
            return "URLSessionTask failed with error: \(error.localizedDescription)"
        }
    }
}

extension AFError.ParameterEncodingFailureReason {
    var localizedDescription: String {
        switch self {
        case .missingURL:
            return "URL request to encode was missing a URL"
        case let .jsonEncodingFailed(error):
            return "JSON could not be encoded because of error:\n\(error.localizedDescription)"
        case let .customEncodingFailed(error):
            return "Custom parameter encoder failed with error: \(error.localizedDescription)"
        }
    }
}

extension AFError.ParameterEncoderFailureReason {
    var localizedDescription: String {
        switch self {
        case let .missingRequiredComponent(component):
            return "Encoding failed due to a missing request component: \(component)"
        case let .encoderFailed(error):
            return "The underlying encoder failed with the error: \(error)"
        }
    }
}

extension AFError.MultipartEncodingFailureReason {
    var localizedDescription: String {
        switch self {
        case let .bodyPartURLInvalid(url):
            return "The URL provided is not a file URL: \(url)"
        case let .bodyPartFilenameInvalid(url):
            return "The URL provided does not have a valid filename: \(url)"
        case let .bodyPartFileNotReachable(url):
            return "The URL provided is not reachable: \(url)"
        case let .bodyPartFileNotReachableWithError(url, error):
            return """
            The system returned an error while checking the provided URL for reachability.
            URL: \(url)
            Error: \(error)
            """
        case let .bodyPartFileIsDirectory(url):
            return "The URL provided is a directory: \(url)"
        case let .bodyPartFileSizeNotAvailable(url):
            return "Could not fetch the file size from the provided URL: \(url)"
        case let .bodyPartFileSizeQueryFailedWithError(url, error):
            return """
            The system returned an error while attempting to fetch the file size from the provided URL.
            URL: \(url)
            Error: \(error)
            """
        case let .bodyPartInputStreamCreationFailed(url):
            return "Failed to create an InputStream for the provided URL: \(url)"
        case let .outputStreamCreationFailed(url):
            return "Failed to create an OutputStream for URL: \(url)"
        case let .outputStreamFileAlreadyExists(url):
            return "A file already exists at the provided URL: \(url)"
        case let .outputStreamURLInvalid(url):
            return "The provided OutputStream URL is invalid: \(url)"
        case let .outputStreamWriteFailed(error):
            return "OutputStream write failed with error: \(error)"
        case let .inputStreamReadFailed(error):
            return "InputStream read failed with error: \(error)"
        }
    }
}

extension AFError.ResponseSerializationFailureReason {
    var localizedDescription: String {
        switch self {
        case .inputDataNilOrZeroLength:
            return "Response could not be serialized, input data was nil or zero length."
        case .inputFileNil:
            return "Response could not be serialized, input file was nil."
        case let .inputFileReadFailed(url):
            return "Response could not be serialized, input file could not be read: \(url)."
        case let .stringSerializationFailed(encoding):
            return "String could not be serialized with encoding: \(encoding)."
        case let .jsonSerializationFailed(error):
            return "JSON could not be serialized because of error:\n\(error.localizedDescription)"
        case let .invalidEmptyResponse(type):
            return """
            Empty response could not be serialized to type: \(type). \
            Use Empty as the expected type for such responses.
            """
        case let .decodingFailed(error):
            return "Response could not be decoded because of error:\n\(error.localizedDescription)"
        case let .customSerializationFailed(error):
            return "Custom response serializer failed with error:\n\(error.localizedDescription)"
        }
    }
}

extension AFError.ResponseValidationFailureReason {
    var localizedDescription: String {
        switch self {
        case .dataFileNil:
            return "Response could not be validated, data file was nil."
        case let .dataFileReadFailed(url):
            return "Response could not be validated, data file could not be read: \(url)."
        case let .missingContentType(types):
            return """
            Response Content-Type was missing and acceptable content types \
            (\(types.joined(separator: ","))) do not match "*/*".
            """
        case let .unacceptableContentType(acceptableTypes, responseType):
            return """
            Response Content-Type "\(responseType)" does not match any acceptable types: \
            \(acceptableTypes.joined(separator: ",")).
            """
        case let .unacceptableStatusCode(code):
            return "Response status code was unacceptable: \(code)."
        case let .customValidationFailed(error):
            return "Custom response validation failed with error: \(error.localizedDescription)"
        }
    }
}

#if !(os(Linux) || os(Windows))
extension AFError.ServerTrustFailureReason {
    var localizedDescription: String {
        switch self {
        case let .noRequiredEvaluator(host):
            return "A ServerTrustEvaluating value is required for host \(host) but none was found."
        case .noCertificatesFound:
            return "No certificates were found or provided for evaluation."
        case .noPublicKeysFound:
            return "No public keys were found or provided for evaluation."
        case .policyApplicationFailed:
            return "Attempting to set a SecPolicy failed."
        case .settingAnchorCertificatesFailed:
            return "Attempting to set the provided certificates as anchor certificates failed."
        case .revocationPolicyCreationFailed:
            return "Attempting to create a revocation policy failed."
        case let .trustEvaluationFailed(error):
            return "SecTrust evaluation failed with error: \(error?.localizedDescription ?? "None")"
        case let .defaultEvaluationFailed(output):
            return "Default evaluation failed for host \(output.host)."
        case let .hostValidationFailed(output):
            return "Host validation failed for host \(output.host)."
        case let .revocationCheckFailed(output, _):
            return "Revocation check failed for host \(output.host)."
        case let .certificatePinningFailed(host, _, _, _):
            return "Certificate pinning failed for host \(host)."
        case let .publicKeyPinningFailed(host, _, _, _):
            return "Public key pinning failed for host \(host)."
        case let .customEvaluationFailed(error):
            return "Custom trust evaluation failed with error: \(error.localizedDescription)"
        }
    }
}
#endif

extension AFError.URLRequestValidationFailureReason {
    var localizedDescription: String {
        switch self {
        case let .bodyDataInGETRequest(data):
            return """
            Invalid URLRequest: Requests with GET method cannot have body data:
            \(String(decoding: data, as: UTF8.self))
            """
        }
    }
}
