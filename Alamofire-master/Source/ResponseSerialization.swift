//
//  ResponseSerialization.swift
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

// MARK: Protocols

/// The type to which all data response serializers must conform in order to serialize a response.
/// 把请求+响应头+响应Data+错误一起使用接口的方法序列化成泛型响应对象
/// 只供DataResponse 使用
public protocol DataResponseSerializerProtocol {
    /// The type of serialized object to be created.
    /// 序列化后的数据类型
    associatedtype SerializedObject

    /// Serialize the response `Data` into the provided type..
    ///
    /// - Parameters:
    ///   - request:  `URLRequest` which was used to perform the request, if any.
    ///   - response: `HTTPURLResponse` received from the server, if any.
    ///   - data:     `Data` returned from the server, if any.
    ///   - error:    `Error` produced by Alamofire or the underlying `URLSession` during the request.
    ///
    /// - Returns:    The `SerializedObject`.
    /// - Throws:     Any `Error` produced during serialization.
    func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> SerializedObject
}

/// The type to which all download response serializers must conform in order to serialize a response.
/// 给DownloadResponse 请求使用
public protocol DownloadResponseSerializerProtocol {
    /// The type of serialized object to be created.
    /// 序列化后的数据类型
    associatedtype SerializedObject

    /// Serialize the downloaded response `Data` from disk into the provided type..
    ///
    /// - Parameters:
    ///   - request:  `URLRequest` which was used to perform the request, if any.
    ///   - response: `HTTPURLResponse` received from the server, if any.
    ///   - fileURL:  File `URL` to which the response data was downloaded.
    ///   - error:    `Error` produced by Alamofire or the underlying `URLSession` during the request.
    ///
    /// - Returns:    The `SerializedObject`.
    /// - Throws:     Any `Error` produced during serialization.
    func serializeDownload(request: URLRequest?, response: HTTPURLResponse?, fileURL: URL?, error: Error?) throws -> SerializedObject
}

/// A serializer that can handle both data and download responses.
/// 默认行为下，若返回的响应Data为空，会被当做请求失败处理，但是实际上比如Head请求，没有响应Data。响应码为204（No Content），205（Reset Content）也是只有响应头，没有响应Data。但是不能当做请求失败处理，因此ResponseSerializer添加了两个Set属性来存放允许响应Data为空的HTTPMethod与响应码。
public protocol ResponseSerializer: DataResponseSerializerProtocol & DownloadResponseSerializerProtocol {
    /// `DataPreprocessor` used to prepare incoming `Data` for serialization.
    /// Data 预处理器, 用来在序列化之前对Data 进行预处理
    var dataPreprocessor: DataPreprocessor { get }
    /// `HTTPMethod`s for which empty response bodies are considered appropriate.
    /// 允许响应data 为空的请求Method(默认HEAD请求的响应data为nil)
    var emptyRequestMethods: Set<HTTPMethod> { get }
    /// HTTP response codes for which empty response bodies are considered appropriate.
    /// 允许响应data 为空的错误码(默认[204, 205]的响应码data为nil)
    var emptyResponseCodes: Set<Int> { get }
}

/// Type used to preprocess `Data` before it handled by a serializer.
/// 用来预处理Data 的协议, Alamofire 有两个默认实现
public protocol DataPreprocessor {
    /// Process           `Data` before it's handled by a serializer.
    /// - Parameter data: The raw `Data` to process.
    /// 出入参均为Data, 允许抛出异常, 抛出异常时封装为AFError返回
    func preprocess(_ data: Data) throws -> Data
}

/// `DataPreprocessor` that returns passed `Data` without any transform.
/// 默认透传处理器, 不做任何处理
public struct PassthroughPreprocessor: DataPreprocessor {
    public init() {}

    public func preprocess(_ data: Data) throws -> Data { data }
}

/// `DataPreprocessor` that trims Google's typical `)]}',\n` XSSI JSON header.
/// 去掉数据前缀的)]}',\n六个字符
/// 预处理谷歌的XSSI 数据, 去掉前6 个字符
public struct GoogleXSSIPreprocessor: DataPreprocessor {
    public init() {}

    public func preprocess(_ data: Data) throws -> Data {
        (data.prefix(6) == Data(")]}',\n".utf8)) ? data.dropFirst(6) : data
    }
}

#if swift(>=5.5)
extension DataPreprocessor where Self == PassthroughPreprocessor {
    /// Provides a `PassthroughPreprocessor` instance.
    public static var passthrough: PassthroughPreprocessor { PassthroughPreprocessor() }
}

extension DataPreprocessor where Self == GoogleXSSIPreprocessor {
    /// Provides a `GoogleXSSIPreprocessor` instance.
    public static var googleXSSI: GoogleXSSIPreprocessor { GoogleXSSIPreprocessor() }
}
#endif

extension ResponseSerializer {
    /// Default `DataPreprocessor`. `PassthroughPreprocessor` by default.
    /// 扩展协议, 给三个属性添加默认实现
    /// 默认的Data 预处理器为透传处理, 不做任何处理
    public static var defaultDataPreprocessor: DataPreprocessor { PassthroughPreprocessor() }
    /// Default `HTTPMethod`s for which empty response bodies are considered appropriate. `[.head]` by default.
    /// 默认允许空Data 的Method 为HEAD
    public static var defaultEmptyRequestMethods: Set<HTTPMethod> { [.head] }
    /// HTTP response codes for which empty response bodies are considered appropriate. `[204, 205]` by default.
    /// 默认允许空Data 的状态码为204, 205
    public static var defaultEmptyResponseCodes: Set<Int> { [204, 205] }
    // 三个属性的默认实现
    public var dataPreprocessor: DataPreprocessor { Self.defaultDataPreprocessor }
    public var emptyRequestMethods: Set<HTTPMethod> { Self.defaultEmptyRequestMethods }
    public var emptyResponseCodes: Set<Int> { Self.defaultEmptyResponseCodes }

    /// Determines whether the `request` allows empty response bodies, if `request` exists.
    ///
    /// - Parameter request: `URLRequest` to evaluate.
    ///
    /// - Returns:           `Bool` representing the outcome of the evaluation, or `nil` if `request` was `nil`.
    /// 检测request 是否允许响应Data为空
    /// 使用的是可选类型的map 跟flatMap 方法, 可选类型的map 跟flatMap 的方法的参数为数据类型, 返回的类型也是可选类型, 当值不为nil 时就会调用闭包, 为nil 时直接返回nil
    public func requestAllowsEmptyResponseData(_ request: URLRequest?) -> Bool? {
        request.flatMap(\.httpMethod)
            .flatMap(HTTPMethod.init)
            .map { emptyRequestMethods.contains($0) }
    }

    /// Determines whether the `response` allows empty response bodies, if `response` exists`.
    ///
    /// - Parameter response: `HTTPURLResponse` to evaluate.
    ///
    /// - Returns:            `Bool` representing the outcome of the evaluation, or `nil` if `response` was `nil`.
    /// 检测响应的状态码是否允许Data 为空
    public func responseAllowsEmptyResponseData(_ response: HTTPURLResponse?) -> Bool? {
        response.map(\.statusCode)
            .map { emptyResponseCodes.contains($0) }
    }

    /// Determines whether `request` and `response` allow empty response bodies.
    ///
    /// - Parameters:
    ///   - request:  `URLRequest` to evaluate.
    ///   - response: `HTTPURLResponse` to evaluate.
    ///
    /// - Returns:    `true` if `request` or `response` allow empty bodies, `false` otherwise.
    /// 组合上面两个检测方法
    public func emptyResponseAllowed(forRequest request: URLRequest?, response: HTTPURLResponse?) -> Bool {
        (requestAllowsEmptyResponseData(request) == true) || (responseAllowsEmptyResponseData(response) == true)
    }
}

/// By default, any serializer declared to conform to both types will get file serialization for free, as it just feeds
/// the data read from disk into the data response serializer.
/// 给即符合DownloadResponseSerializerProtocol 又符合DataResponseSerializerProtocol 协议的类型提供默认实现
/// 只要先把数据从文件里读出来就可以作为Data去实现DataResponseSerializerProtocol的序列化方法
/// 注意大文件直接读出来会爆内存
extension DownloadResponseSerializerProtocol where Self: DataResponseSerializerProtocol {
    public func serializeDownload(request: URLRequest?, response: HTTPURLResponse?, fileURL: URL?, error: Error?) throws -> Self.SerializedObject {
        guard error == nil else { throw error! }

        guard let fileURL = fileURL else {
            throw AFError.responseSerializationFailed(reason: .inputFileNil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AFError.responseSerializationFailed(reason: .inputFileReadFailed(at: fileURL))
        }
        // DataResponseSerializerProtocol 的序列化逻辑, catch错误并抛出
        do {
            return try serialize(request: request, response: response, data: data, error: error)
        } catch {
            throw error
        }
    }
}

// MARK: - Default

extension DataRequest {
    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:             The queue on which the completion handler is dispatched. `.main` by default.
    ///   - completionHandler: The code to be executed once the request has finished.
    ///
    /// - Returns:             The request.
    /// 普通解析, 只是封装Data
    @discardableResult
    public func response(queue: DispatchQueue = .main, completionHandler: @escaping (AFDataResponse<Data?>) -> Void) -> Self {
        // appendResponseSerializer 是一个参数为闭包, 无返回值的方法, 尾随闭包写法第一眼看起来容易疑问
        appendResponseSerializer {
            // Start work that should be on the serialization queue.
            // 开始解析响应, 必须在解析队列完成
            // 默认不解析, 直接封装下Data
            let result = AFResult<Data?>(value: self.data, error: self.error)
            // End work that should be on the serialization queue.
            // 响应解析完成
            // 解析完成后的行为需要在对应队列完成
            self.underlyingQueue.async {
                // 封装
                let response = DataResponse(request: self.request,
                                            response: self.response,
                                            data: self.data,
                                            metrics: self.metrics,
                                            serializationDuration: 0,
                                            result: result)
                // 告知监听器
                self.eventMonitor?.request(self, didParseResponse: response)
                // 回调解析完成
                self.responseSerializerDidComplete { queue.async { completionHandler(response) } }
            }
        }

        return self
    }
    // 使用自定义解析器解析
    private func _response<Serializer: DataResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                       responseSerializer: Serializer,
                                                                       completionHandler: @escaping (AFDataResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        appendResponseSerializer {
            // Start work that should be on the serialization queue.
            // 开始解析响应, 必须在响应解析队列完成, 因为有解析操作, 所以开始计时
            let start = ProcessInfo.processInfo.systemUptime
            // 用入参解析器解析数据, catch 错误并转换成AFError
            let result: AFResult<Serializer.SerializedObject> = Result {
                try responseSerializer.serialize(request: self.request,
                                                 response: self.response,
                                                 data: self.data,
                                                 error: self.error)
            }.mapError { error in
                error.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: error)))
            }
            // 用app 启动的时间差值来计算出解析所花时间
            let end = ProcessInfo.processInfo.systemUptime
            // End work that should be on the serialization queue.
            // 解析完成
            // 回Request 内部队列来继续处理
            self.underlyingQueue.async {
                // 组装DataResponse, Success 类型为序列化协议中的泛型SerializedObject 类型
                let response = DataResponse(request: self.request,
                                            response: self.response,
                                            data: self.data,
                                            metrics: self.metrics,
                                            serializationDuration: end - start,
                                            result: result)
                // 告知监听器
                self.eventMonitor?.request(self, didParseResponse: response)

                guard let serializerError = result.failure, let delegate = self.delegate else {
                    // 如果解析成功, 直接走完成逻辑
                    self.responseSerializerDidComplete { queue.async { completionHandler(response) } }
                    return
                }
                // 解析出错, 准备重试
                delegate.retryResult(for: self, dueTo: serializerError) { retryResult in
                    // 是否完成的回调, nil 表示要重试
                    var didComplete: (() -> Void)?

                    defer {
                        if let didComplete = didComplete {
                            self.responseSerializerDidComplete { queue.async { didComplete() } }
                        }
                    }
                    // 根据参数retryResult 判断是否重试
                    switch retryResult {
                    case .doNotRetry: // 不重试, 直接完成
                        didComplete = { completionHandler(response) }

                    case let .doNotRetryWithError(retryError): // 不重试, 把error 替换掉
                        // 用新的retryError 初始化result
                        let result: AFResult<Serializer.SerializedObject> = .failure(retryError.asAFError(orFailWith: "Received retryError was not already AFError"))
                        // 封装新的Response
                        let response = DataResponse(request: self.request,
                                                    response: self.response,
                                                    data: self.data,
                                                    metrics: self.metrics,
                                                    serializationDuration: end - start,
                                                    result: result)

                        didComplete = { completionHandler(response) }

                    case .retry, .retryWithDelay:
                        delegate.retryRequest(self, withDelay: retryResult.delay)
                    }
                }
            }
        }

        return self
    }

    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:              The queue on which the completion handler is dispatched. `.main` by default
    ///   - responseSerializer: The response serializer responsible for serializing the request, response, and data.
    ///   - completionHandler:  The code to be executed once the request has finished.
    ///
    /// - Returns:              The request.
    @discardableResult
    public func response<Serializer: DataResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                     responseSerializer: Serializer,
                                                                     completionHandler: @escaping (AFDataResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }

    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:              The queue on which the completion handler is dispatched. `.main` by default
    ///   - responseSerializer: The response serializer responsible for serializing the request, response, and data.
    ///   - completionHandler:  The code to be executed once the request has finished.
    ///
    /// - Returns:              The request.
    @discardableResult
    public func response<Serializer: ResponseSerializer>(queue: DispatchQueue = .main,
                                                         responseSerializer: Serializer,
                                                         completionHandler: @escaping (AFDataResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }
}

extension DownloadRequest {
    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:             The queue on which the completion handler is dispatched. `.main` by default.
    ///   - completionHandler: The code to be executed once the request has finished.
    ///
    /// - Returns:             The request.
    /// 普通处理下载响应, 下载数据以文件url 形式回调处理, 文件url 为可选类型
    @discardableResult
    public func response(queue: DispatchQueue = .main,
                         completionHandler: @escaping (AFDownloadResponse<URL?>) -> Void)
        -> Self {
        appendResponseSerializer {
            // Start work that should be on the serialization queue.
            let result = AFResult<URL?>(value: self.fileURL, error: self.error)
            // End work that should be on the serialization queue.

            self.underlyingQueue.async {
                let response = DownloadResponse(request: self.request,
                                                response: self.response,
                                                fileURL: self.fileURL,
                                                resumeData: self.resumeData,
                                                metrics: self.metrics,
                                                serializationDuration: 0,
                                                result: result)

                self.eventMonitor?.request(self, didParseResponse: response)

                self.responseSerializerDidComplete { queue.async { completionHandler(response) } }
            }
        }

        return self
    }
    // 使用自定义序列化器来处理下载响应
    private func _response<Serializer: DownloadResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                           responseSerializer: Serializer,
                                                                           completionHandler: @escaping (AFDownloadResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        appendResponseSerializer {
            // Start work that should be on the serialization queue.
            let start = ProcessInfo.processInfo.systemUptime
            let result: AFResult<Serializer.SerializedObject> = Result {
                try responseSerializer.serializeDownload(request: self.request,
                                                         response: self.response,
                                                         fileURL: self.fileURL,
                                                         error: self.error)
            }.mapError { error in
                error.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: error)))
            }
            let end = ProcessInfo.processInfo.systemUptime
            // End work that should be on the serialization queue.

            self.underlyingQueue.async {
                let response = DownloadResponse(request: self.request,
                                                response: self.response,
                                                fileURL: self.fileURL,
                                                resumeData: self.resumeData,
                                                metrics: self.metrics,
                                                serializationDuration: end - start,
                                                result: result)

                self.eventMonitor?.request(self, didParseResponse: response)

                guard let serializerError = result.failure, let delegate = self.delegate else {
                    self.responseSerializerDidComplete { queue.async { completionHandler(response) } }
                    return
                }

                delegate.retryResult(for: self, dueTo: serializerError) { retryResult in
                    var didComplete: (() -> Void)?

                    defer {
                        if let didComplete = didComplete {
                            self.responseSerializerDidComplete { queue.async { didComplete() } }
                        }
                    }

                    switch retryResult {
                    case .doNotRetry:
                        didComplete = { completionHandler(response) }

                    case let .doNotRetryWithError(retryError):
                        let result: AFResult<Serializer.SerializedObject> = .failure(retryError.asAFError(orFailWith: "Received retryError was not already AFError"))

                        let response = DownloadResponse(request: self.request,
                                                        response: self.response,
                                                        fileURL: self.fileURL,
                                                        resumeData: self.resumeData,
                                                        metrics: self.metrics,
                                                        serializationDuration: end - start,
                                                        result: result)

                        didComplete = { completionHandler(response) }

                    case .retry, .retryWithDelay:
                        delegate.retryRequest(self, withDelay: retryResult.delay)
                    }
                }
            }
        }

        return self
    }

    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:              The queue on which the completion handler is dispatched. `.main` by default.
    ///   - responseSerializer: The response serializer responsible for serializing the request, response, and data
    ///                         contained in the destination `URL`.
    ///   - completionHandler:  The code to be executed once the request has finished.
    ///
    /// - Returns:              The request.
    @discardableResult
    public func response<Serializer: DownloadResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                         responseSerializer: Serializer,
                                                                         completionHandler: @escaping (AFDownloadResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }

    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:              The queue on which the completion handler is dispatched. `.main` by default.
    ///   - responseSerializer: The response serializer responsible for serializing the request, response, and data
    ///                         contained in the destination `URL`.
    ///   - completionHandler:  The code to be executed once the request has finished.
    ///
    /// - Returns:              The request.
    @discardableResult
    public func response<Serializer: ResponseSerializer>(queue: DispatchQueue = .main,
                                                         responseSerializer: Serializer,
                                                         completionHandler: @escaping (AFDownloadResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }
}

// MARK: - URL

/// A `DownloadResponseSerializerProtocol` that performs only `Error` checking and ensures that a downloaded `fileURL`
/// is present.
public struct URLResponseSerializer: DownloadResponseSerializerProtocol {
    /// Creates an instance.
    public init() {}

    public func serializeDownload(request: URLRequest?,
                                  response: HTTPURLResponse?,
                                  fileURL: URL?,
                                  error: Error?) throws -> URL {
        guard error == nil else { throw error! }

        guard let url = fileURL else {
            throw AFError.responseSerializationFailed(reason: .inputFileNil)
        }

        return url
    }
}

#if swift(>=5.5)
extension DownloadResponseSerializerProtocol where Self == URLResponseSerializer {
    /// Provides a `URLResponseSerializer` instance.
    public static var url: URLResponseSerializer { URLResponseSerializer() }
}
#endif

extension DownloadRequest {
    /// Adds a handler using a `URLResponseSerializer` to be called once the request is finished.
    ///
    /// - Parameters:
    ///   - queue:             The queue on which the completion handler is called. `.main` by default.
    ///   - completionHandler: A closure to be executed once the request has finished.
    ///
    /// - Returns:             The request.
    @discardableResult
    public func responseURL(queue: DispatchQueue = .main,
                            completionHandler: @escaping (AFDownloadResponse<URL>) -> Void) -> Self {
        response(queue: queue, responseSerializer: URLResponseSerializer(), completionHandler: completionHandler)
    }
}

// MARK: - Data

/// A `ResponseSerializer` that performs minimal response checking and returns any response `Data` as-is. By default, a
/// request returning `nil` or no data is considered an error. However, if the request has an `HTTPMethod` or the
/// response has an  HTTP status code valid for empty responses, then an empty `Data` value is returned.
/// 定义DataResponseSerializer 序列化器实现ResponseSerializer 协议并修饰为final，不可继承
/// 可预处理Data，处理空Data
/// 序列化数据为Data类型
/// 扩展DataRequest 与DownloadRequest 添加responseData 序列化方法
public final class DataResponseSerializer: ResponseSerializer {
    // 实现ResponseSerializer 协议的三个属性
    public let dataPreprocessor: DataPreprocessor
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>

    /// Creates a `DataResponseSerializer` using the provided parameters.
    ///
    /// - Parameters:
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    public init(dataPreprocessor: DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) {
        self.dataPreprocessor = dataPreprocessor
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
    }

    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> Data {
        guard error == nil else { throw error! }
        // 如果data空, (包括nil, 空Data), 调用协议扩展的检测是否允许空Data的方法
        guard var data = data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                // 不允许空Data 就抛出错误
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }
            // 空Data, 就返回一个空的Data对象
            return Data()
        }
        // 预处理Data
        data = try dataPreprocessor.preprocess(data)
        // 返回类型为Data
        return data
    }
}

#if swift(>=5.5)
extension ResponseSerializer where Self == DataResponseSerializer {
    /// Provides a default `DataResponseSerializer` instance.
    public static var data: DataResponseSerializer { DataResponseSerializer() }

    /// Creates a `DataResponseSerializer` using the provided parameters.
    ///
    /// - Parameters:
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    ///
    /// - Returns:               The `DataResponseSerializer`.
    public static func data(dataPreprocessor: DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                            emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                            emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) -> DataResponseSerializer {
        DataResponseSerializer(dataPreprocessor: dataPreprocessor,
                               emptyResponseCodes: emptyResponseCodes,
                               emptyRequestMethods: emptyRequestMethods)
    }
}
#endif
// 扩展DataRequest, 添加解析响应回调
extension DataRequest {
    /// Adds a handler using a `DataResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:               The queue on which the completion handler is called. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @discardableResult
    public func responseData(queue: DispatchQueue = .main,
                             dataPreprocessor: DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                             emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                             emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods,
                             completionHandler: @escaping (AFDataResponse<Data>) -> Void) -> Self {
        // 调用上面通用的使用序列化协议对象解析的方法
        response(queue: queue,
                 responseSerializer: DataResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}

extension DownloadRequest {
    /// Adds a handler using a `DataResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:               The queue on which the completion handler is called. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @discardableResult
    public func responseData(queue: DispatchQueue = .main,
                             dataPreprocessor: DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                             emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                             emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods,
                             completionHandler: @escaping (AFDownloadResponse<Data>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: DataResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}

// MARK: - String

/// A `ResponseSerializer` that decodes the response data as a `String`. By default, a request returning `nil` or no
/// data is considered an error. However, if the request has an `HTTPMethod` or the response has an  HTTP status code
/// valid for empty responses, then an empty `String` is returned.
/// 可指定String 编码格式, 默认为.isoLatin1. 优先级：手动设置 > 服务器返回 > 默认的isoLatin1
/// 可预处理Data，处理空Data
/// 序列化数据为Data 类型
/// 扩展DataRequest 与DownloadRequest 添加responseString 序列化方法
public final class StringResponseSerializer: ResponseSerializer {
    public let dataPreprocessor: DataPreprocessor
    /// Optional string encoding used to validate the response.
    /// string 编码格式
    public let encoding: String.Encoding?
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>

    /// Creates an instance with the provided values.
    ///
    /// - Parameters:
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - encoding:            A string encoding. Defaults to `nil`, in which case the encoding will be determined
    ///                          from the server response, falling back to the default HTTP character set, `ISO-8859-1`.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    public init(dataPreprocessor: DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                encoding: String.Encoding? = nil,
                emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) {
        self.dataPreprocessor = dataPreprocessor
        self.encoding = encoding
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
    }

    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> String {
        guard error == nil else { throw error! }
        // 先检测下空data 情况, 抛出异常或者是返回空字符串
        guard var data = data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }

            return ""
        }
        // 预处理Data
        data = try dataPreprocessor.preprocess(data)
        // string 编码格式
        var convertedEncoding = encoding

        if let encodingName = response?.textEncodingName, convertedEncoding == nil {
            // 未指定编码格式, 且服务器有返回编码格式
            convertedEncoding = String.Encoding(ianaCharsetName: encodingName)
        }
        // 实际编码格式: 手动设置 > 服务器返回 > 默认的isoLatin1
        let actualEncoding = convertedEncoding ?? .isoLatin1
        // 编码, 编码失败抛出错误
        guard let string = String(data: data, encoding: actualEncoding) else {
            throw AFError.responseSerializationFailed(reason: .stringSerializationFailed(encoding: actualEncoding))
        }

        return string
    }
}

#if swift(>=5.5)
extension ResponseSerializer where Self == StringResponseSerializer {
    /// Provides a default `StringResponseSerializer` instance.
    public static var string: StringResponseSerializer { StringResponseSerializer() }

    /// Creates a `StringResponseSerializer` with the provided values.
    ///
    /// - Parameters:
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - encoding:            A string encoding. Defaults to `nil`, in which case the encoding will be determined
    ///                          from the server response, falling back to the default HTTP character set, `ISO-8859-1`.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    ///
    /// - Returns:               The `StringResponseSerializer`.
    public static func string(dataPreprocessor: DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                              encoding: String.Encoding? = nil,
                              emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                              emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) -> StringResponseSerializer {
        StringResponseSerializer(dataPreprocessor: dataPreprocessor,
                                 encoding: encoding,
                                 emptyResponseCodes: emptyResponseCodes,
                                 emptyRequestMethods: emptyRequestMethods)
    }
}
#endif
// 添加解析方法responseString
extension DataRequest {
    /// Adds a handler using a `StringResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:               The queue on which the completion handler is dispatched. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - encoding:            The string encoding. Defaults to `nil`, in which case the encoding will be determined
    ///                          from the server response, falling back to the default HTTP character set, `ISO-8859-1`.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @discardableResult
    public func responseString(queue: DispatchQueue = .main,
                               dataPreprocessor: DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                               encoding: String.Encoding? = nil,
                               emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                               emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods,
                               completionHandler: @escaping (AFDataResponse<String>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: StringResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                              encoding: encoding,
                                                              emptyResponseCodes: emptyResponseCodes,
                                                              emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}

extension DownloadRequest {
    /// Adds a handler using a `StringResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:               The queue on which the completion handler is dispatched. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - encoding:            The string encoding. Defaults to `nil`, in which case the encoding will be determined
    ///                          from the server response, falling back to the default HTTP character set, `ISO-8859-1`.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @discardableResult
    public func responseString(queue: DispatchQueue = .main,
                               dataPreprocessor: DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                               encoding: String.Encoding? = nil,
                               emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                               emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods,
                               completionHandler: @escaping (AFDownloadResponse<String>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: StringResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                              encoding: encoding,
                                                              emptyResponseCodes: emptyResponseCodes,
                                                              emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}

// MARK: - JSON

/// A `ResponseSerializer` that decodes the response data using `JSONSerialization`. By default, a request returning
/// `nil` or no data is considered an error. However, if the request has an `HTTPMethod` or the response has an
/// HTTP status code valid for empty responses, then an `NSNull` value is returned.
/// 可指定JSON 读取格式，默认为.allowFragments
/// 使用系统的JSONSerialization 解析Data
/// 扩展DataRequest 与DownloadRequest 添加responseJSON 序列化方法
@available(*, deprecated, message: "JSONResponseSerializer deprecated and will be removed in Alamofire 6. Use DecodableResponseSerializer instead.")
public final class JSONResponseSerializer: ResponseSerializer {
    public let dataPreprocessor: DataPreprocessor
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>
    /// `JSONSerialization.ReadingOptions` used when serializing a response.
    /// JSON 读取格式
    public let options: JSONSerialization.ReadingOptions

    /// Creates an instance with the provided values.
    ///
    /// - Parameters:
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    ///   - options:             The options to use. `.allowFragments` by default.
    public init(dataPreprocessor: DataPreprocessor = JSONResponseSerializer.defaultDataPreprocessor,
                emptyResponseCodes: Set<Int> = JSONResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = JSONResponseSerializer.defaultEmptyRequestMethods,
                options: JSONSerialization.ReadingOptions = .allowFragments) {
        self.dataPreprocessor = dataPreprocessor
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
        self.options = options
    }
    // 实现协议的解析方法
    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> Any {
        guard error == nil else { throw error! }

        guard var data = data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }

            return NSNull()
        }
        // 预处理
        data = try dataPreprocessor.preprocess(data)

        do {
            // 序列化JSON
            return try JSONSerialization.jsonObject(with: data, options: options)
        } catch {
            throw AFError.responseSerializationFailed(reason: .jsonSerializationFailed(error: error))
        }
    }
}
// 添加响应方法responseJSON
extension DataRequest {
    /// Adds a handler using a `JSONResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:               The queue on which the completion handler is dispatched. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - options:             `JSONSerialization.ReadingOptions` used when parsing the response. `.allowFragments`
    ///                          by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @available(*, deprecated, message: "responseJSON deprecated and will be removed in Alamofire 6. Use responseDecodable instead.")
    @discardableResult
    public func responseJSON(queue: DispatchQueue = .main,
                             dataPreprocessor: DataPreprocessor = JSONResponseSerializer.defaultDataPreprocessor,
                             emptyResponseCodes: Set<Int> = JSONResponseSerializer.defaultEmptyResponseCodes,
                             emptyRequestMethods: Set<HTTPMethod> = JSONResponseSerializer.defaultEmptyRequestMethods,
                             options: JSONSerialization.ReadingOptions = .allowFragments,
                             completionHandler: @escaping (AFDataResponse<Any>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: JSONResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods,
                                                            options: options),
                 completionHandler: completionHandler)
    }
}

extension DownloadRequest {
    /// Adds a handler using a `JSONResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:               The queue on which the completion handler is dispatched. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - options:             `JSONSerialization.ReadingOptions` used when parsing the response. `.allowFragments`
    ///                          by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @available(*, deprecated, message: "responseJSON deprecated and will be removed in Alamofire 6. Use responseDecodable instead.")
    @discardableResult
    public func responseJSON(queue: DispatchQueue = .main,
                             dataPreprocessor: DataPreprocessor = JSONResponseSerializer.defaultDataPreprocessor,
                             emptyResponseCodes: Set<Int> = JSONResponseSerializer.defaultEmptyResponseCodes,
                             emptyRequestMethods: Set<HTTPMethod> = JSONResponseSerializer.defaultEmptyRequestMethods,
                             options: JSONSerialization.ReadingOptions = .allowFragments,
                             completionHandler: @escaping (AFDownloadResponse<Any>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: JSONResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods,
                                                            options: options),
                 completionHandler: completionHandler)
    }
}

// MARK: - Empty

/// Protocol representing an empty response. Use `T.emptyValue()` to get an instance.
public protocol EmptyResponse {
    /// Empty value for the conforming type.
    ///
    /// - Returns: Value of `Self` to use for empty values.
    static func emptyValue() -> Self
}

/// Type representing an empty value. Use `Empty.value` to get the static instance.
public struct Empty: Codable {
    /// Static `Empty` instance used for all `Empty` responses.
    public static let value = Empty()
}

extension Empty: EmptyResponse {
    public static func emptyValue() -> Empty {
        value
    }
}

// MARK: - DataDecoder Protocol

/// Any type which can decode `Data` into a `Decodable` type.
public protocol DataDecoder {
    /// Decode `Data` into the provided type.
    ///
    /// - Parameters:
    ///   - type:  The `Type` to be decoded.
    ///   - data:  The `Data` to be decoded.
    ///
    /// - Returns: The decoded value of type `D`.
    /// - Throws:  Any error that occurs during decode.
    func decode<D: Decodable>(_ type: D.Type, from data: Data) throws -> D
}

/// `JSONDecoder` automatically conforms to `DataDecoder`.
extension JSONDecoder: DataDecoder {}
/// `PropertyListDecoder` automatically conforms to `DataDecoder`.
extension PropertyListDecoder: DataDecoder {}

// MARK: - Decodable

/// A `ResponseSerializer` that decodes the response data as a generic value using any type that conforms to
/// `DataDecoder`. By default, this is an instance of `JSONDecoder`. Additionally, a request returning `nil` or no data
/// is considered an error. However, if the request has an `HTTPMethod` or the response has an HTTP status code valid
/// for empty responses then an empty value will be returned. If the decoded type conforms to `EmptyResponse`, the
/// type's `emptyValue()` will be returned. If the decoded type is `Empty`, the `.value` instance is returned. If the
/// decoded type *does not* conform to `EmptyResponse` and isn't `Empty`, an error will be produced.
public final class DecodableResponseSerializer<T: Decodable>: ResponseSerializer {
    public let dataPreprocessor: DataPreprocessor
    /// The `DataDecoder` instance used to decode responses.
    /// 用来解码的解码器, 默认为系统JSONDecoder 解码器
    public let decoder: DataDecoder
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>

    /// Creates an instance using the values provided.
    ///
    /// - Parameters:
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - decoder:             The `DataDecoder`. `JSONDecoder()` by default.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    public init(dataPreprocessor: DataPreprocessor = DecodableResponseSerializer.defaultDataPreprocessor,
                decoder: DataDecoder = JSONDecoder(),
                emptyResponseCodes: Set<Int> = DecodableResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer.defaultEmptyRequestMethods) {
        self.dataPreprocessor = dataPreprocessor
        self.decoder = decoder
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
    }
    // 实现ResponseSerializer 协议的解析方法
    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: Error?) throws -> T {
        guard error == nil else { throw error! }
        // 处理空数据
        guard var data = data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }
            // 从解析结果类型T, 获取空数据常量
            guard let emptyResponseType = T.self as? EmptyResponse.Type, let emptyValue = emptyResponseType.emptyValue() as? T else {
                throw AFError.responseSerializationFailed(reason: .invalidEmptyResponse(type: "\(T.self)"))
            }

            return emptyValue
        }

        data = try dataPreprocessor.preprocess(data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AFError.responseSerializationFailed(reason: .decodingFailed(error: error))
        }
    }
}

#if swift(>=5.5)
extension ResponseSerializer {
    /// Creates a `DecodableResponseSerializer` using the values provided.
    ///
    /// - Parameters:
    ///   - type:                `Decodable` type to decode from response data.
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - decoder:             The `DataDecoder`. `JSONDecoder()` by default.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    ///
    /// - Returns:               The `DecodableResponseSerializer`.
    public static func decodable<T: Decodable>(of type: T.Type,
                                               dataPreprocessor: DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                               decoder: DataDecoder = JSONDecoder(),
                                               emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                               emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods) -> DecodableResponseSerializer<T> where Self == DecodableResponseSerializer<T> {
        DecodableResponseSerializer<T>(dataPreprocessor: dataPreprocessor,
                                       decoder: decoder,
                                       emptyResponseCodes: emptyResponseCodes,
                                       emptyRequestMethods: emptyRequestMethods)
    }
}
#endif

extension DataRequest {
    /// Adds a handler using a `DecodableResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - type:                `Decodable` type to decode from response data.
    ///   - queue:               The queue on which the completion handler is dispatched. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - decoder:             `DataDecoder` to use to decode the response. `JSONDecoder()` by default.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @discardableResult
    public func responseDecodable<T: Decodable>(of type: T.Type = T.self,
                                                queue: DispatchQueue = .main,
                                                dataPreprocessor: DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                                decoder: DataDecoder = JSONDecoder(),
                                                emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                                emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods,
                                                completionHandler: @escaping (AFDataResponse<T>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: DecodableResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                                 decoder: decoder,
                                                                 emptyResponseCodes: emptyResponseCodes,
                                                                 emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}

extension DownloadRequest {
    /// Adds a handler using a `DecodableResponseSerializer` to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - type:                `Decodable` type to decode from response data.
    ///   - queue:               The queue on which the completion handler is dispatched. `.main` by default.
    ///   - dataPreprocessor:    `DataPreprocessor` which processes the received `Data` before calling the
    ///                          `completionHandler`. `PassthroughPreprocessor()` by default.
    ///   - decoder:             `DataDecoder` to use to decode the response. `JSONDecoder()` by default.
    ///   - emptyResponseCodes:  HTTP status codes for which empty responses are always valid. `[204, 205]` by default.
    ///   - emptyRequestMethods: `HTTPMethod`s for which empty responses are always valid. `[.head]` by default.
    ///   - completionHandler:   A closure to be executed once the request has finished.
    ///
    /// - Returns:               The request.
    @discardableResult
    public func responseDecodable<T: Decodable>(of type: T.Type = T.self,
                                                queue: DispatchQueue = .main,
                                                dataPreprocessor: DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                                decoder: DataDecoder = JSONDecoder(),
                                                emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                                emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods,
                                                completionHandler: @escaping (AFDownloadResponse<T>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: DecodableResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                                 decoder: decoder,
                                                                 emptyResponseCodes: emptyResponseCodes,
                                                                 emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}

// MARK: - DataStreamRequest

/// A type which can serialize incoming `Data`.
/// 该方法只用解析Data, 不用解析Request与Response.
public protocol DataStreamSerializer {
    /// Type produced from the serialized `Data`.
    /// 序列化结果泛型
    associatedtype SerializedObject

    /// Serializes incoming `Data` into a `SerializedObject` value.
    ///
    /// - Parameter data: `Data` to be serialized.
    ///
    /// - Throws: Any error produced during serialization.
    /// 序列化方法
    func serialize(_ data: Data) throws -> SerializedObject
}

/// `DataStreamSerializer` which uses the provided `DataPreprocessor` and `DataDecoder` to serialize the incoming `Data`.
public struct DecodableStreamSerializer<T: Decodable>: DataStreamSerializer {
    /// `DataDecoder` used to decode incoming `Data`.
    public let decoder: DataDecoder
    /// `DataPreprocessor` incoming `Data` is passed through before being passed to the `DataDecoder`.
    public let dataPreprocessor: DataPreprocessor

    /// Creates an instance with the provided `DataDecoder` and `DataPreprocessor`.
    /// - Parameters:
    ///   - decoder: `        DataDecoder` used to decode incoming `Data`. `JSONDecoder()` by default.
    ///   - dataPreprocessor: `DataPreprocessor` used to process incoming `Data` before it's passed through the
    ///                       `decoder`. `PassthroughPreprocessor()` by default.
    public init(decoder: DataDecoder = JSONDecoder(), dataPreprocessor: DataPreprocessor = PassthroughPreprocessor()) {
        self.decoder = decoder
        self.dataPreprocessor = dataPreprocessor
    }

    public func serialize(_ data: Data) throws -> T {
        let processedData = try dataPreprocessor.preprocess(data)
        do {
            return try decoder.decode(T.self, from: processedData)
        } catch {
            throw AFError.responseSerializationFailed(reason: .decodingFailed(error: error))
        }
    }
}

/// `DataStreamSerializer` which performs no serialization on incoming `Data`.
public struct PassthroughStreamSerializer: DataStreamSerializer {
    /// Creates an instance.
    public init() {}

    public func serialize(_ data: Data) throws -> Data { data }
}

/// `DataStreamSerializer` which serializes incoming stream `Data` into `UTF8`-decoded `String` values.
public struct StringStreamSerializer: DataStreamSerializer {
    /// Creates an instance.
    public init() {}

    public func serialize(_ data: Data) throws -> String {
        String(decoding: data, as: UTF8.self)
    }
}

#if swift(>=5.5)
extension DataStreamSerializer {
    /// Creates a `DecodableStreamSerializer` instance with the provided `DataDecoder` and `DataPreprocessor`.
    ///
    /// - Parameters:
    ///   - type:             `Decodable` type to decode from stream data.
    ///   - decoder: `        DataDecoder` used to decode incoming `Data`. `JSONDecoder()` by default.
    ///   - dataPreprocessor: `DataPreprocessor` used to process incoming `Data` before it's passed through the
    ///                       `decoder`. `PassthroughPreprocessor()` by default.
    public static func decodable<T: Decodable>(of type: T.Type,
                                               decoder: DataDecoder = JSONDecoder(),
                                               dataPreprocessor: DataPreprocessor = PassthroughPreprocessor()) -> Self where Self == DecodableStreamSerializer<T> {
        DecodableStreamSerializer<T>(decoder: decoder, dataPreprocessor: dataPreprocessor)
    }
}

extension DataStreamSerializer where Self == PassthroughStreamSerializer {
    /// Provides a `PassthroughStreamSerializer` instance.
    public static var passthrough: PassthroughStreamSerializer { PassthroughStreamSerializer() }
}

extension DataStreamSerializer where Self == StringStreamSerializer {
    /// Provides a `StringStreamSerializer` instance.
    public static var string: StringStreamSerializer { StringStreamSerializer() }
}
#endif

extension DataStreamRequest {
    /// Adds a `StreamHandler` which performs no parsing on incoming `Data`.
    ///
    /// - Parameters:
    ///   - queue:  `DispatchQueue` on which to perform `StreamHandler` closure.
    ///   - stream: `StreamHandler` closure called as `Data` is received. May be called multiple times.
    ///
    /// - Returns:  The `DataStreamRequest`.
    @discardableResult
    public func responseStream(on queue: DispatchQueue = .main, stream: @escaping Handler<Data, Never>) -> Self {
        // 创建解析回调paser, 然后追加到Request 的解析回调队列里
        let parser = { [unowned self] (data: Data) in
            queue.async {
                self.capturingError {
                    // 执行Handle, 捕捉异常
                    try stream(.init(event: .stream(.success(data)), token: .init(self)))
                }
                // 更新状态, 并检测是否需要完成
                self.updateAndCompleteIfPossible()
            }
        }
        // 追加解析回调
        $streamMutableState.write { $0.streams.append(parser) }
        // 把完成回调追加给Handle
        appendStreamCompletion(on: queue, stream: stream)

        return self
    }

    /// Adds a `StreamHandler` which uses the provided `DataStreamSerializer` to process incoming `Data`.
    ///
    /// - Parameters:
    ///   - serializer: `DataStreamSerializer` used to process incoming `Data`. Its work is done on the `serializationQueue`.
    ///   - queue:      `DispatchQueue` on which to perform `StreamHandler` closure.
    ///   - stream:     `StreamHandler` closure called as `Data` is received. May be called multiple times.
    ///
    /// - Returns:      The `DataStreamRequest`.
    @discardableResult
    public func responseStream<Serializer: DataStreamSerializer>(using serializer: Serializer,
                                                                 on queue: DispatchQueue = .main,
                                                                 stream: @escaping Handler<Serializer.SerializedObject, AFError>) -> Self {
        let parser = { [unowned self] (data: Data) in
            self.serializationQueue.async {
                // Start work on serialization queue.
                let result = Result { try serializer.serialize(data) }
                    .mapError { $0.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: $0))) }
                // End work on serialization queue.
                self.underlyingQueue.async {
                    self.eventMonitor?.request(self, didParseStream: result)

                    if result.isFailure, self.automaticallyCancelOnStreamError {
                        self.cancel()
                    }

                    queue.async {
                        self.capturingError {
                            try stream(.init(event: .stream(result), token: .init(self)))
                        }

                        self.updateAndCompleteIfPossible()
                    }
                }
            }
        }

        $streamMutableState.write { $0.streams.append(parser) }
        appendStreamCompletion(on: queue, stream: stream)

        return self
    }

    /// Adds a `StreamHandler` which parses incoming `Data` as a UTF8 `String`.
    ///
    /// - Parameters:
    ///   - queue:      `DispatchQueue` on which to perform `StreamHandler` closure.
    ///   - stream:     `StreamHandler` closure called as `Data` is received. May be called multiple times.
    ///
    /// - Returns:  The `DataStreamRequest`.
    @discardableResult
    public func responseStreamString(on queue: DispatchQueue = .main,
                                     stream: @escaping Handler<String, Never>) -> Self {
        let parser = { [unowned self] (data: Data) in
            self.serializationQueue.async {
                // Start work on serialization queue.
                let string = String(decoding: data, as: UTF8.self)
                // End work on serialization queue.
                self.underlyingQueue.async {
                    self.eventMonitor?.request(self, didParseStream: .success(string))

                    queue.async {
                        self.capturingError {
                            try stream(.init(event: .stream(.success(string)), token: .init(self)))
                        }

                        self.updateAndCompleteIfPossible()
                    }
                }
            }
        }

        $streamMutableState.write { $0.streams.append(parser) }
        appendStreamCompletion(on: queue, stream: stream)

        return self
    }
    // 更新流的个数
    private func updateAndCompleteIfPossible() {
        $streamMutableState.write { state in
            state.numberOfExecutingStreams -= 1

            guard state.numberOfExecutingStreams == 0, !state.enqueuedCompletionEvents.isEmpty else { return }

            let completionEvents = state.enqueuedCompletionEvents
            self.underlyingQueue.async { completionEvents.forEach { $0() } }
            state.enqueuedCompletionEvents.removeAll()
        }
    }

    /// Adds a `StreamHandler` which parses incoming `Data` using the provided `DataDecoder`.
    ///
    /// - Parameters:
    ///   - type:         `Decodable` type to parse incoming `Data` into.
    ///   - queue:        `DispatchQueue` on which to perform `StreamHandler` closure.
    ///   - decoder:      `DataDecoder` used to decode the incoming `Data`.
    ///   - preprocessor: `DataPreprocessor` used to process the incoming `Data` before it's passed to the `decoder`.
    ///   - stream:       `StreamHandler` closure called as `Data` is received. May be called multiple times.
    ///
    /// - Returns: The `DataStreamRequest`.
    @discardableResult
    public func responseStreamDecodable<T: Decodable>(of type: T.Type = T.self,
                                                      on queue: DispatchQueue = .main,
                                                      using decoder: DataDecoder = JSONDecoder(),
                                                      preprocessor: DataPreprocessor = PassthroughPreprocessor(),
                                                      stream: @escaping Handler<T, AFError>) -> Self {
        responseStream(using: DecodableStreamSerializer<T>(decoder: decoder, dataPreprocessor: preprocessor),
                       stream: stream)
    }
}
