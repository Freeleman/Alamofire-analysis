//
//  CachedResponseHandler.swift
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

/// A type that handles whether the data task should store the HTTP response in the cache.
public protocol CachedResponseHandler {
    /// Determines whether the HTTP response should be stored in the cache.
    ///
    /// The `completion` closure should be passed one of three possible options:
    ///
    ///   1. The cached response provided by the server (this is the most common use case).
    ///   2. A modified version of the cached response (you may want to modify it in some way before caching).
    ///   3. A `nil` value to prevent the cached response from being stored in the cache.
    ///
    /// - Parameters:
    ///   - task:       The data task whose request resulted in the cached response.
    ///   - response:   The cached response to potentially store in the cache.
    ///   - completion: The closure to execute containing cached response, a modified response, or `nil`.
    func dataTask(_ task: URLSessionDataTask,
                  willCacheResponse response: CachedURLResponse,
                  completion: @escaping (CachedURLResponse?) -> Void)
}

// MARK: -

/// `ResponseCacher` is a convenience `CachedResponseHandler` making it easy to cache, not cache, or modify a cached
/// response.
public struct ResponseCacher {
    /// Defines the behavior of the `ResponseCacher` type.
    /// 定义处理缓存的行为
    public enum Behavior {
        /// Stores the cached response in the cache.
        /// 缓存原始数据
        case cache
        /// Prevents the cached response from being stored in the cache.
        /// 不缓存
        case doNotCache
        /// Modifies the cached response before storing it in the cache.
        /// 先修改数据, 再缓存新数据, 参数为修改数据的闭包, 改闭包返回可选的新缓存数据
        case modify((URLSessionDataTask, CachedURLResponse) -> CachedURLResponse?)
    }

    /// Returns a `ResponseCacher` with a `.cache` `Behavior`.
    /// 快速初始化缓存原始数据的对象
    public static let cache = ResponseCacher(behavior: .cache)
    /// Returns a `ResponseCacher` with a `.doNotCache` `Behavior`.
    /// 快速初始化不缓存数据的对象
    public static let doNotCache = ResponseCacher(behavior: .doNotCache)

    /// The `Behavior` of the `ResponseCacher`.
    /// 缓存行为
    public let behavior: Behavior

    /// Creates a `ResponseCacher` instance from the `Behavior`.
    ///
    /// - Parameter behavior: The `Behavior`.
    /// 初始化
    public init(behavior: Behavior) {
        self.behavior = behavior
    }
}

extension ResponseCacher: CachedResponseHandler {
    public func dataTask(_ task: URLSessionDataTask,
                         willCacheResponse response: CachedURLResponse,
                         completion: @escaping (CachedURLResponse?) -> Void) {
        switch behavior {
        case .cache:
            // 直接调用completion, 缓存原数据
            completion(response)
        case .doNotCache:
            // 传nil 不缓存
            completion(nil)
        case let .modify(closure):
            // 修改, 先调用参数closure, 获取修改参数, 然后传给completion
            let response = closure(task, response)
            completion(response)
        }
    }
}

#if swift(>=5.5)
extension CachedResponseHandler where Self == ResponseCacher {
    /// Provides a `ResponseCacher` which caches the response, if allowed. Equivalent to `ResponseCacher.cache`.
    public static var cache: ResponseCacher { .cache }

    /// Provides a `ResponseCacher` which does not cache the response. Equivalent to `ResponseCacher.doNotCache`.
    public static var doNotCache: ResponseCacher { .doNotCache }

    /// Creates a `ResponseCacher` which modifies the proposed `CachedURLResponse` using the provided closure.
    ///
    /// - Parameter closure: Closure used to modify the `CachedURLResponse`.
    /// - Returns:           The `ResponseCacher`.
    public static func modify(using closure: @escaping ((URLSessionDataTask, CachedURLResponse) -> CachedURLResponse?)) -> ResponseCacher {
        ResponseCacher(behavior: .modify(closure))
    }
}
#endif
