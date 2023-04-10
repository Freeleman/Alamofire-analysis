//
//  RequestInterceptor.swift
//
//  Copyright (c) 2019 Alamofire Software Foundation (http://alamofire.org/)
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

/// Stores all state associated with a `URLRequest` being adapted.
public struct RequestAdapterState {
    /// The `UUID` of the `Request` associated with the `URLRequest` to adapt.
    public let requestID: UUID

    /// The `Session` associated with the `URLRequest` to adapt.
    public let session: Session
}

// MARK: -

/// A type that can inspect and optionally adapt a `URLRequest` in some manner if necessary.
/// 请求适配器, 请求的预处理
public protocol RequestAdapter {
    /// Inspects and adapts the specified `URLRequest` in some manner and calls the completion handler with the Result.
    ///
    /// - Parameters:
    ///   - urlRequest: The `URLRequest` to adapt.
    ///   - session:    The `Session` that will execute the `URLRequest`.
    ///   - completion: The completion handler that must be called when adaptation is complete.
    /// 入参为初始URLRequest, Session 以及适配完成后的回调, 回调参数为Result 对象, 可以为成功适配后的URLRequest 对象, 也可以返回错误, 会向上抛出从创建requestAdaptationFailed 错误
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void)

    /// Inspects and adapts the specified `URLRequest` in some manner and calls the completion handler with the Result.
    ///
    /// - Parameters:
    ///   - urlRequest: The `URLRequest` to adapt.
    ///   - state:      The `RequestAdapterState` associated with the `URLRequest`.
    ///   - completion: The completion handler that must be called when adaptation is complete.
    func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void)
}

extension RequestAdapter {
    public func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, for: state.session, completion: completion)
    }
}

// MARK: -

/// Outcome of determination whether retry is necessary.
public enum RetryResult {
    /// Retry should be attempted immediately.
    /// 立刻
    case retry
    /// Retry should be attempted after the associated `TimeInterval`.
    /// 延迟
    case retryWithDelay(TimeInterval)
    /// Do not retry.
    /// 不重试
    case doNotRetry
    /// Do not retry due to the associated `Error`.
    /// 不重试, 抛出错误
    case doNotRetryWithError(Error)
}

// 快速取得相关信息, 两个可选值属性方便快速做出判断
extension RetryResult {
    // 是否需要重试
    var retryRequired: Bool {
        switch self {
        case .retry, .retryWithDelay: return true
        default: return false
        }
    }
    // 延迟重试时间
    var delay: TimeInterval? {
        switch self {
        case let .retryWithDelay(delay): return delay
        default: return nil
        }
    }
    // 不重试抛出错误信息
    var error: Error? {
        guard case let .doNotRetryWithError(error) = self else { return nil }
        return error
    }
}

/// A type that determines whether a request should be retried after being executed by the specified session manager
/// and encountering an error.
/// 请求重试器, 响应的预处理
public protocol RequestRetrier {
    /// Determines whether the `Request` should be retried by calling the `completion` closure.
    ///
    /// This operation is fully asynchronous. Any amount of time can be taken to determine whether the request needs
    /// to be retried. The one requirement is that the completion closure is called to ensure the request is properly
    /// cleaned up after.
    ///
    /// - Parameters:
    ///   - request:    `Request` that failed due to the provided `Error`.
    ///   - session:    `Session` that produced the `Request`.
    ///   - error:      `Error` encountered while executing the `Request`.
    ///   - completion: Completion closure to be executed when a retry decision has been determined.
    /// 参数为: Request 对象, Session, 请求失败的错误信息以及重试逻辑回调, 回调参数为重试逻辑, 调用者根据该逻辑决定重试行为
    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void)
}

// MARK: -

/// Type that provides both `RequestAdapter` and `RequestRetrier` functionality.
/// 组合协议 RequestAdapter, RequestRetrier
public protocol RequestInterceptor: RequestAdapter, RequestRetrier {}
// 扩展, 使得即便遵循协议也可以不实现方法, 依旧不会报错
extension RequestInterceptor {
    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        // 直接返回原请求
        completion(.success(urlRequest))
    }

    public func retry(_ request: Request,
                      for session: Session,
                      dueTo error: Error,
                      completion: @escaping (RetryResult) -> Void) {
        // 不重试
        completion(.doNotRetry)
    }
}

/// `RequestAdapter` closure definition.
/// 定义一个用来适配请求的闭包
public typealias AdaptHandler = (URLRequest, Session, _ completion: @escaping (Result<URLRequest, Error>) -> Void) -> Void
/// `RequestRetrier` closure definition.
/// 定义一个用来决定重试逻辑的闭包
public typealias RetryHandler = (Request, Session, Error, _ completion: @escaping (RetryResult) -> Void) -> Void

// MARK: -

/// Closure-based `RequestAdapter`.
/// 实现基于闭包的重试器
open class Adapter: RequestInterceptor {
    private let adaptHandler: AdaptHandler

    /// Creates an instance using the provided closure.
    ///
    /// - Parameter adaptHandler: `AdaptHandler` closure to be executed when handling request adaptation.
    public init(_ adaptHandler: @escaping AdaptHandler) {
        self.adaptHandler = adaptHandler
    }

    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adaptHandler(urlRequest, session, completion)
    }

    open func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adaptHandler(urlRequest, state.session, completion)
    }
}

#if swift(>=5.5)
extension RequestAdapter where Self == Adapter {
    /// Creates an `Adapter` using the provided `AdaptHandler` closure.
    ///
    /// - Parameter closure: `AdaptHandler` to use to adapt the request.
    /// - Returns:           The `Adapter`.
    public static func adapter(using closure: @escaping AdaptHandler) -> Adapter {
        Adapter(closure)
    }
}
#endif

// MARK: -

/// Closure-based `RequestRetrier`.
/// 实现基于闭包的重试器
open class Retrier: RequestInterceptor {
    private let retryHandler: RetryHandler

    /// Creates an instance using the provided closure.
    ///
    /// - Parameter retryHandler: `RetryHandler` closure to be executed when handling request retry.
    public init(_ retryHandler: @escaping RetryHandler) {
        self.retryHandler = retryHandler
    }

    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: Error,
                    completion: @escaping (RetryResult) -> Void) {
        retryHandler(request, session, error, completion)
    }
}

#if swift(>=5.5)
extension RequestRetrier where Self == Retrier {
    /// Creates a `Retrier` using the provided `RetryHandler` closure.
    ///
    /// - Parameter closure: `RetryHandler` to use to retry the request.
    /// - Returns:           The `Retrier`.
    public static func retrier(using closure: @escaping RetryHandler) -> Retrier {
        Retrier(closure)
    }
}
#endif

// MARK: -

/// `RequestInterceptor` which can use multiple `RequestAdapter` and `RequestRetrier` values.
/// 持有多个适配器和重试器
/// 持有两个数组, 一个保存适配器对象, 一个保存重试器对象, 重试时, 顺序处理, 注意传入时的顺序
open class Interceptor: RequestInterceptor {
    /// All `RequestAdapter`s associated with the instance. These adapters will be run until one fails.
    /// 保存适配器, 有任何一个出现错误, 就会抛出错误
    public let adapters: [RequestAdapter]
    /// All `RequestRetrier`s associated with the instance. These retriers will be run one at a time until one triggers retry.
    /// 保存重试器, 有任何一个初选需要重试, 立即重试或者延迟重试, 就会停止, 然后抛出需要重试, 有任何一个不重试并抛出错误也会立即停止, 抛出错误
    public let retriers: [RequestRetrier]

    /// Creates an instance from `AdaptHandler` and `RetryHandler` closures.
    ///
    /// - Parameters:
    ///   - adaptHandler: `AdaptHandler` closure to be used.
    ///   - retryHandler: `RetryHandler` closure to be used.
    ///   也可以使用重试器与适配器回调来创建单个的组合器
    public init(adaptHandler: @escaping AdaptHandler, retryHandler: @escaping RetryHandler) {
        adapters = [Adapter(adaptHandler)]
        retriers = [Retrier(retryHandler)]
    }

    /// Creates an instance from `RequestAdapter` and `RequestRetrier` values.
    ///
    /// - Parameters:
    ///   - adapter: `RequestAdapter` value to be used.
    ///   - retrier: `RequestRetrier` value to be used.
    ///   用两个数组初始化
    public init(adapter: RequestAdapter, retrier: RequestRetrier) {
        adapters = [adapter]
        retriers = [retrier]
    }

    /// Creates an instance from the arrays of `RequestAdapter` and `RequestRetrier` values.
    ///
    /// - Parameters:
    ///   - adapters:     `RequestAdapter` values to be used.
    ///   - retriers:     `RequestRetrier` values to be used.
    ///   - interceptors: `RequestInterceptor`s to be used.
    ///   用适配器 + 重试器 + 拦截器 数组初始化, 会把拦截器数组均加入到适配器与重试器数组中
    public init(adapters: [RequestAdapter] = [], retriers: [RequestRetrier] = [], interceptors: [RequestInterceptor] = []) {
        self.adapters = adapters + interceptors
        self.retriers = retriers + interceptors
    }
    // 适配器代理方法, 调用下面的私有方法
    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, for: session, using: adapters, completion: completion)
    }
    // 私有适配器方法, 递归调用
    private func adapt(_ urlRequest: URLRequest,
                       for session: Session,
                       using adapters: [RequestAdapter],
                       completion: @escaping (Result<URLRequest, Error>) -> Void) {
        // 准备递归的数组
        var pendingAdapters = adapters
        // 递归空, 执行回调返回
        guard !pendingAdapters.isEmpty else { completion(.success(urlRequest)); return }
        // 取出第一个适配去
        let adapter = pendingAdapters.removeFirst()
        // 继续执行
        adapter.adapt(urlRequest, for: session) { result in
            switch result {
                //适配通过, 递归剩下的
            case let .success(urlRequest):
                self.adapt(urlRequest, for: session, using: pendingAdapters, completion: completion)
            case .failure:
                // 失败, 抛出错误
                completion(result)
            }
        }
    }
    // 重试
    open func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, using: state, adapters: adapters, completion: completion)
    }
    // 重试逻辑, 递归调用, 逻辑同上
    private func adapt(_ urlRequest: URLRequest,
                       using state: RequestAdapterState,
                       adapters: [RequestAdapter],
                       completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var pendingAdapters = adapters

        guard !pendingAdapters.isEmpty else { completion(.success(urlRequest)); return }

        let adapter = pendingAdapters.removeFirst()

        adapter.adapt(urlRequest, using: state) { result in
            switch result {
            case let .success(urlRequest):
                self.adapt(urlRequest, using: state, adapters: pendingAdapters, completion: completion)
            case .failure:
                completion(result)
            }
        }
    }

    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: Error,
                    completion: @escaping (RetryResult) -> Void) {
        retry(request, for: session, dueTo: error, using: retriers, completion: completion)
    }

    private func retry(_ request: Request,
                       for session: Session,
                       dueTo error: Error,
                       using retriers: [RequestRetrier],
                       completion: @escaping (RetryResult) -> Void) {
        var pendingRetriers = retriers

        guard !pendingRetriers.isEmpty else { completion(.doNotRetry); return }

        let retrier = pendingRetriers.removeFirst()

        retrier.retry(request, for: session, dueTo: error) { result in
            switch result {
            case .retry, .retryWithDelay, .doNotRetryWithError:
                completion(result)
            case .doNotRetry:
                // Only continue to the next retrier if retry was not triggered and no error was encountered
                self.retry(request, for: session, dueTo: error, using: pendingRetriers, completion: completion)
            }
        }
    }
}

#if swift(>=5.5)
extension RequestInterceptor where Self == Interceptor {
    /// Creates an `Interceptor` using the provided `AdaptHandler` and `RetryHandler` closures.
    ///
    /// - Parameters:
    ///   - adapter: `AdapterHandler`to use to adapt the request.
    ///   - retrier: `RetryHandler` to use to retry the request.
    /// - Returns:   The `Interceptor`.
    public static func interceptor(adapter: @escaping AdaptHandler, retrier: @escaping RetryHandler) -> Interceptor {
        Interceptor(adaptHandler: adapter, retryHandler: retrier)
    }

    /// Creates an `Interceptor` using the provided `RequestAdapter` and `RequestRetrier` instances.
    /// - Parameters:
    ///   - adapter: `RequestAdapter` to use to adapt the request
    ///   - retrier: `RequestRetrier` to use to retry the request.
    /// - Returns:   The `Interceptor`.
    public static func interceptor(adapter: RequestAdapter, retrier: RequestRetrier) -> Interceptor {
        Interceptor(adapter: adapter, retrier: retrier)
    }

    /// Creates an `Interceptor` using the provided `RequestAdapter`s, `RequestRetrier`s, and `RequestInterceptor`s.
    /// - Parameters:
    ///   - adapters:     `RequestAdapter`s to use to adapt the request. These adapters will be run until one fails.
    ///   - retriers:     `RequestRetrier`s to use to retry the request. These retriers will be run one at a time until
    ///                   a retry is triggered.
    ///   - interceptors: `RequestInterceptor`s to use to intercept the request.
    /// - Returns:        The `Interceptor`.
    public static func interceptor(adapters: [RequestAdapter] = [],
                                   retriers: [RequestRetrier] = [],
                                   interceptors: [RequestInterceptor] = []) -> Interceptor {
        Interceptor(adapters: adapters, retriers: retriers, interceptors: interceptors)
    }
}
#endif
