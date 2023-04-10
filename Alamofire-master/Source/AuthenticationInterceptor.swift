//
//  AuthenticationInterceptor.swift
//
//  Copyright (c) 2020 Alamofire Software Foundation (http://alamofire.org/)
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

/// Types adopting the `AuthenticationCredential` protocol can be used to authenticate `URLRequest`s.
///
/// One common example of an `AuthenticationCredential` is an OAuth2 credential containing an access token used to
/// authenticate all requests on behalf of a user. The access token generally has an expiration window of 60 minutes
/// which will then require a refresh of the credential using the refresh token to generate a new access token.
public protocol AuthenticationCredential {
    /// Whether the credential requires a refresh. This property should always return `true` when the credential is
    /// expired. It is also wise to consider returning `true` when the credential will expire in several seconds or
    /// minutes depending on the expiration window of the credential.
    ///
    /// For example, if the credential is valid for 60 minutes, then it would be wise to return `true` when the
    /// credential is only valid for 5 minutes or less. That ensures the credential will not expire as it is passed
    /// around backend services.
    /// 是否需要刷新凭证, 如果返回false, 下面的Authenticator 接口对象将会调用刷新方法来刷新凭证
    /// 要注意的时, 比如凭证有效期是60min, 那么最好在过期前5 分钟的时候, 就要返回true 刷新凭证了, 避免后续请求中凭证过期
    var requiresRefresh: Bool { get }
}

// MARK: -

/// Types adopting the `Authenticator` protocol can be used to authenticate `URLRequest`s with an
/// `AuthenticationCredential` as well as refresh the `AuthenticationCredential` when required.
public protocol Authenticator: AnyObject {
    /// The type of credential associated with the `Authenticator` instance.
    /// 身份验证凭据泛型
    associatedtype Credential: AuthenticationCredential

    /// Applies the `Credential` to the `URLRequest`.
    ///
    /// In the case of OAuth2, the access token of the `Credential` would be added to the `URLRequest` as a Bearer
    /// token to the `Authorization` header.
    ///
    /// - Parameters:
    ///   - credential: The `Credential`.
    ///   - urlRequest: The `URLRequest`.
    /// 把凭证应用到请求
    /// 例如OAuth2 认证, 就会把凭证中的access token 添加到请求头里去
    func apply(_ credential: Credential, to urlRequest: inout URLRequest)

    /// Refreshes the `Credential` and executes the `completion` closure with the `Result` once complete.
    ///
    /// Refresh can be called in one of two ways. It can be called before the `Request` is actually executed due to
    /// a `requiresRefresh` returning `true` during the adapt portion of the `Request` creation process. It can also
    /// be triggered by a failed `Request` where the authentication server denied access due to an expired or
    /// invalidated access token.
    ///
    /// In the case of OAuth2, this method would use the refresh token of the `Credential` to generate a new
    /// `Credential` using the authentication service. Once complete, the `completion` closure should be called with
    /// the new `Credential`, or the error that occurred.
    ///
    /// In general, if the refresh call fails with certain status codes from the authentication server (commonly a 401),
    /// the refresh token in the `Credential` can no longer be used to generate a valid `Credential`. In these cases,
    /// you will need to reauthenticate the user with their username / password.
    ///
    /// Please note, these are just general examples of common use cases. They are not meant to solve your specific
    /// authentication server challenges. Please work with your authentication server team to ensure your
    /// `Authenticator` logic matches their expectations.
    ///
    /// - Parameters:
    ///   - credential: The `Credential` to refresh.
    ///   - session:    The `Session` requiring the refresh.
    ///   - completion: The closure to be executed once the refresh is complete.
    /// 刷新凭证, 完成闭包是个可逃逸闭包
    /// 刷新方法会有两种调用情况:
    ///   1.当请求准备发送时, 如果凭证需要被刷新, 拦截器就会调用验证者的刷新方法来刷新凭证后再发出请求
    ///   2.当请求响应失败时, 拦截器会通过询问验证者是否是身份认证失败, 如果是身份认证失败, 就会调用刷新方法, 然后重试请求
    /// 注意, 如果是OAuth2, 就会出现分歧, 当请求收到需要验证身份时, 这个验证要求到底是来自于内容服务器?还是来自于验证服务器?如果是来自于内容服务器, 那么只需要验证者刷新凭证, 拦截器重试请求即可, 如果是来自于验证服务器, 那么就需要抛出错误, 让用户重新进行登录才行.
    /// 使用的时候, 如果用的OAuth2, 需要跟后台小伙伴协商区分两种身份验证的情况. 拦截器会根据下一个方法来判断是不是身份验证失败了.
    func refresh(_ credential: Credential, for session: Session, completion: @escaping (Result<Credential, Error>) -> Void)

    /// Determines whether the `URLRequest` failed due to an authentication error based on the `HTTPURLResponse`.
    ///
    /// If the authentication server **CANNOT** invalidate credentials after they are issued, then simply return `false`
    /// for this method. If the authentication server **CAN** invalidate credentials due to security breaches, then you
    /// will need to work with your authentication server team to understand how to identify when this occurs.
    ///
    /// In the case of OAuth2, where an authentication server can invalidate credentials, you will need to inspect the
    /// `HTTPURLResponse` or possibly the `Error` for when this occurs. This is commonly handled by the authentication
    /// server returning a 401 status code and some additional header to indicate an OAuth2 failure occurred.
    ///
    /// It is very important to understand how your authentication server works to be able to implement this correctly.
    /// For example, if your authentication server returns a 401 when an OAuth2 error occurs, and your downstream
    /// service also returns a 401 when you are not authorized to perform that operation, how do you know which layer
    /// of the backend returned you a 401? You do not want to trigger a refresh unless you know your authentication
    /// server is actually the layer rejecting the request. Again, work with your authentication server team to understand
    /// how to identify an OAuth2 401 error vs. a downstream 401 error to avoid endless refresh loops.
    ///
    /// - Parameters:
    ///   - urlRequest: The `URLRequest`.
    ///   - response:   The `HTTPURLResponse`.
    ///   - error:      The `Error`.
    ///
    /// - Returns: `true` if the `URLRequest` failed due to an authentication error, `false` otherwise.
    /// 判断请求失败是不是因为身份验证服务器导致的. 若身份验证服务器颁发的凭证不会失效, 该方法简单返回false就行.
    /// 如果身份验证服务器颁发的凭证会失效, 当请求碰到比如401错误时, 就要判断, 验证请求来自何方. 若来自内容服务器, 那就需要验证者刷新凭证重试请求即可, 若来自验证服务器, 就得抛出错误让用户重新登录. 具体如何判定, 需要跟后台开发小伙伴协商
    /// 因此若该协议方法返回true, 拦截器就不会重试请求, 而是直接抛出错误
    /// 若该方法返回false, 拦截器就会根据下面的方法判断凭证是否有效, 有效的话直接重试, 无效的话会先让验证者刷新凭证后再重试
    func didRequest(_ urlRequest: URLRequest, with response: HTTPURLResponse, failDueToAuthenticationError error: Error) -> Bool

    /// Determines whether the `URLRequest` is authenticated with the `Credential`.
    ///
    /// If the authentication server **CANNOT** invalidate credentials after they are issued, then simply return `true`
    /// for this method. If the authentication server **CAN** invalidate credentials due to security breaches, then
    /// read on.
    ///
    /// When an authentication server can invalidate credentials, it means that you may have a non-expired credential
    /// that appears to be valid, but will be rejected by the authentication server when used. Generally when this
    /// happens, a number of requests are all sent when the application is foregrounded, and all of them will be
    /// rejected by the authentication server in the order they are received. The first failed request will trigger a
    /// refresh internally, which will update the credential, and then retry all the queued requests with the new
    /// credential. However, it is possible that some of the original requests will not return from the authentication
    /// server until the refresh has completed. This is where this method comes in.
    ///
    /// When the authentication server rejects a credential, we need to check to make sure we haven't refreshed the
    /// credential while the request was in flight. If it has already refreshed, then we don't need to trigger an
    /// additional refresh. If it hasn't refreshed, then we need to refresh.
    ///
    /// Now that it is understood how the result of this method is used in the refresh lifecyle, let's walk through how
    /// to implement it. You should return `true` in this method if the `URLRequest` is authenticated in a way that
    /// matches the values in the `Credential`. In the case of OAuth2, this would mean that the Bearer token in the
    /// `Authorization` header of the `URLRequest` matches the access token in the `Credential`. If it matches, then we
    /// know the `Credential` was used to authenticate the `URLRequest` and should return `true`. If the Bearer token
    /// did not match the access token, then you should return `false`.
    ///
    /// - Parameters:
    ///   - urlRequest: The `URLRequest`.
    ///   - credential: The `Credential`.
    ///
    /// - Returns: `true` if the `URLRequest` is authenticated with the `Credential`, `false` otherwise.
    /// 判断当请求失败时, 本次请求有没有被当前的凭证认证过
    /// 如果验证服务器颁发的凭证不会失效, 该方法简单返回true就行
    /*
    若验证服务器颁发的凭证会失效, 就会存在这个情况: 凭证A还在有效期内, 但是已经被认证服务器标记为失效了, 那么在失效后的第一个请求响应时,
    就会触发刷新逻辑, 在刷新过程中, 还会有一系列使用凭证A认证的请求还没落地, 那么当响应触发时,
    就需要根据该方法检测下本次请求是否被当前的凭证认证过.
    如果认证过, 就需要暂存重试回调, 等刷新凭证后, 在执行重试回调.
    如果未认证过, 表示当前持有的凭证可能已经是新的凭证B了, 那么直接重试请求就好
     */
    func isRequest(_ urlRequest: URLRequest, authenticatedWith credential: Credential) -> Bool
}

// MARK: -

/// Represents various authentication failures that occur when using the `AuthenticationInterceptor`. All errors are
/// still vended from Alamofire as `AFError` types. The `AuthenticationError` instances will be embedded within
/// `AFError` `.requestAdaptationFailed` or `.requestRetryFailed` cases.
public enum AuthenticationError: Error {
    /// The credential was missing so the request could not be authenticated.
    /// 凭证丢失
    case missingCredential
    /// The credential was refreshed too many times within the `RefreshWindow`.
    /// 次数过多
    case excessiveRefresh
}

// MARK: -

/// The `AuthenticationInterceptor` class manages the queuing and threading complexity of authenticating requests.
/// It relies on an `Authenticator` type to handle the actual `URLRequest` authentication and `Credential` refresh.
public class AuthenticationInterceptor<AuthenticatorType>: RequestInterceptor where AuthenticatorType: Authenticator {
    // MARK: Typealiases

    /// Type of credential used to authenticate requests.
    /// 凭证别名
    public typealias Credential = AuthenticatorType.Credential

    // MARK: Helper Types

    /// Type that defines a time window used to identify excessive refresh calls. When enabled, prior to executing a
    /// refresh, the `AuthenticationInterceptor` compares the timestamp history of previous refresh calls against the
    /// `RefreshWindow`. If more refreshes have occurred within the refresh window than allowed, the refresh is
    /// cancelled and an `AuthorizationError.excessiveRefresh` error is thrown.
    /// 刷新窗口, 限制指定时间段内的最大刷新次数
    /// 拦截器会持有每次刷新的时间戳, 每次刷新时, 通过遍历时间戳检测在最近的时间段内刷新的次数有没有超过锁限制的最大刷新次数, 超过的话, 就会取消刷新并抛出错误
    public struct RefreshWindow {
        /// `TimeInterval` defining the duration of the time window before the current time in which the number of
        /// refresh attempts is compared against `maximumAttempts`. For example, if `interval` is 30 seconds, then the
        /// `RefreshWindow` represents the past 30 seconds. If more attempts occurred in the past 30 seconds than
        /// `maximumAttempts`, an `.excessiveRefresh` error will be thrown.
        /// 限制周期, 默认30s
        public let interval: TimeInterval

        /// Total refresh attempts allowed within `interval` before throwing an `.excessiveRefresh` error.
        /// 周期内最大刷新次数, 默认5 次
        public let maximumAttempts: Int

        /// Creates a `RefreshWindow` instance from the specified `interval` and `maximumAttempts`.
        ///
        /// - Parameters:
        ///   - interval:        `TimeInterval` defining the duration of the time window before the current time.
        ///   - maximumAttempts: The maximum attempts allowed within the `TimeInterval`.
        public init(interval: TimeInterval = 30.0, maximumAttempts: Int = 5) {
            self.interval = interval
            self.maximumAttempts = maximumAttempts
        }
    }
    // 拦截请求准备对请求进行适配时, 如果需要刷新凭证, 就会把适配方法的参数封装成该结构体暂存在拦截器中, 刷新完成后对保存的所有结构体逐个调用completion 来发送请求
    private struct AdaptOperation {
        let urlRequest: URLRequest
        let session: Session
        let completion: (Result<URLRequest, Error>) -> Void
    }
    // 拦截请求进行适配时的结果, 拦截器会根据不同的适配结果执行不同的逻辑
    private enum AdaptResult {
        // 适配完成, 获取到了凭证, 接下来就要让验证者来把凭证注入到请求中
        case adapt(Credential)
        // 验证失败, 凭证丢失或者刷新次数过多, 会取消发送请求
        case doNotAdapt(AuthenticationError)
        // 正在刷新凭证, 会把适配方法的参数给封装成上面的结构体暂存, 刷新凭证后会继续执行
        case adaptDeferred
    }
    // 可变的状态, 会使用 @Protected 修饰保证线程安全
    private struct MutableState {
        // 凭证, 可能为空
        var credential: Credential?
        // 是否正在刷新凭证
        var isRefreshing = false
        // 刷新凭证的时间戳
        var refreshTimestamps: [TimeInterval] = []
        // 持有的刷新限制窗口
        var refreshWindow: RefreshWindow?
        // 暂存的适配请求的相关参数
        var adaptOperations: [AdaptOperation] = []
        // 暂存的重试请求的完成闭包, 当拦截器对请求失败进行重试处理时, 如果发现需要刷新凭证, 会把完成闭包暂存, 然后让验证者刷新凭证, 之后在逐个遍历该数组, 执行重试逻辑
        var requestsToRetry: [(RetryResult) -> Void] = []
    }

    // MARK: Properties

    /// The `Credential` used to authenticate requests.
    /// 凭证, 直接从mutableState 中线程安全的读写
    public var credential: Credential? {
        get { $mutableState.credential }
        set { $mutableState.credential = newValue }
    }
    // 验证者
    let authenticator: AuthenticatorType
    // 刷新凭证的队列
    let queue = DispatchQueue(label: "org.alamofire.authentication.inspector")
    // 线程安全的状态对象
    @Protected
    private var mutableState: MutableState

    // MARK: Initialization

    /// Creates an `AuthenticationInterceptor` instance from the specified parameters.
    ///
    /// A `nil` `RefreshWindow` will result in the `AuthenticationInterceptor` not checking for excessive refresh calls.
    /// It is recommended to always use a `RefreshWindow` to avoid endless refresh cycles.
    ///
    /// - Parameters:
    ///   - authenticator: The `Authenticator` type.
    ///   - credential:    The `Credential` if it exists. `nil` by default.
    ///   - refreshWindow: The `RefreshWindow` used to identify excessive refresh calls. `RefreshWindow()` by default.
    public init(authenticator: AuthenticatorType,
                credential: Credential? = nil,
                refreshWindow: RefreshWindow? = RefreshWindow()) {
        self.authenticator = authenticator
        mutableState = MutableState(credential: credential, refreshWindow: refreshWindow)
    }

    // MARK: Adapt
    // 适配请求
    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        // 获取适配结果, 需要保证线程安全
        let adaptResult: AdaptResult = $mutableState.write { mutableState in
            // Queue the adapt operation if a refresh is already in place.
            // 检查下是否是已经正在刷新凭证了
            guard !mutableState.isRefreshing else {
                // 正在刷新凭证, 就把所有参数暂存到adaptOperations中, 然后等待刷新完成后再处理这些参数
                let operation = AdaptOperation(urlRequest: urlRequest, session: session, completion: completion)
                mutableState.adaptOperations.append(operation)
                // 返回适配延期
                return .adaptDeferred
            }
            // 没有再刷新凭证, 继续适配
            // 获取凭证
            // Throw missing credential error is the credential is missing.
            guard let credential = mutableState.credential else {
                // 凭证丢失了, 返回错误
                let error = AuthenticationError.missingCredential
                return .doNotAdapt(error)
            }

            // Queue the adapt operation and trigger refresh operation if credential requires refresh.
            // 检测下凭证是否有效
            guard !credential.requiresRefresh else {
                // 凭证过期, 需要刷新, 把参数暂存
                let operation = AdaptOperation(urlRequest: urlRequest, session: session, completion: completion)
                mutableState.adaptOperations.append(operation)
                // 调用刷新凭证方法
                refresh(credential, for: session, insideLock: &mutableState)
                // 返回适配延期
                return .adaptDeferred
            }
            // 凭证有效, 返回适配成功
            return .adapt(credential)
        }
        // 处理适配结果
        switch adaptResult {
        case let .adapt(credential): // 适配成功, 让验证者把凭证注入到请求中
            var authenticatedRequest = urlRequest
            authenticator.apply(credential, to: &authenticatedRequest)
            // 调用完成回调, 返回适配后的请求
            completion(.success(authenticatedRequest))

        case let .doNotAdapt(adaptError):
            // 适配失败, 调用完成回调抛出错误
            completion(.failure(adaptError))

        case .adaptDeferred:
            // No-op: adapt operation captured during refresh.
            // 适配延期, 不做任何处理, 等刷新凭证完成后, 会使用暂存的参数中的completion继续处理
            break
        }
    }

    // MARK: Retry
    // 请求重试
    public func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        // Do not attempt retry if there was not an original request and response from the server.
        // 如果没有url 请求或相应, 不重试
        guard let urlRequest = request.request, let response = request.response else {
            completion(.doNotRetry)
            return
        }

        // Do not attempt retry unless the `Authenticator` verifies failure was due to authentication error (i.e. 401 status code).
        // 问下验证者是否是验证服务器验证失败(OAuth2情况)
        guard authenticator.didRequest(urlRequest, with: response, failDueToAuthenticationError: error) else {
            completion(.doNotRetry)
            return
        }

        // Do not attempt retry if there is no credential.
        // 验证服务器验证失败, 不重试, 直接返回错误, 需要用户重新登录
        guard let credential = credential else {
            let error = AuthenticationError.missingCredential
            completion(.doNotRetryWithError(error))
            return
        }

        // Retry the request if the `Authenticator` verifies it was authenticated with a previous credential.
        // 问下验证者, 请求是否被当前的凭证认证过
        guard authenticator.isRequest(urlRequest, authenticatedWith: credential) else {
            // 如果请求没被当前凭证认证过, 表示这个凭证是新的, 直接重试就好
            completion(.retry)
            return
        }
        // 否则表示当前凭证已经无效了, 需要刷新凭证后再重试
        $mutableState.write { mutableState in
            // 暂存完成回调
            mutableState.requestsToRetry.append(completion)
            // 如果正在刷新凭证, 返回即可
            guard !mutableState.isRefreshing else { return }
            // 当前没有刷新凭证, 调用refresh 开始刷新
            refresh(credential, for: session, insideLock: &mutableState)
        }
    }

    // MARK: Refresh
    // 在刷新前先进行刷新最大次数校验
    // 在请求后保存刷新时间戳，供下次刷新做次数校验
    // 在刷新后对暂存的请求适配结果回调进行处理
    // 在刷新后对暂存的请求重试结果回调进行处理
    private func refresh(_ credential: Credential, for session: Session, insideLock mutableState: inout MutableState) {
        // 检测是否超出最大刷新次数
        guard !isRefreshExcessive(insideLock: &mutableState) else {
            // 超出最大刷新次数了, 走刷新失败逻辑
            let error = AuthenticationError.excessiveRefresh
            handleRefreshFailure(error, insideLock: &mutableState)
            return
        }
        // 保存刷新时间戳
        mutableState.refreshTimestamps.append(ProcessInfo.processInfo.systemUptime)
        // 标记正在刷新
        mutableState.isRefreshing = true

        // Dispatch to queue to hop out of the lock in case authenticator.refresh is implemented synchronously.
        // 在队列里异步调用验证者的刷新方法, 因为拦截器在调用刷新方法前已经上锁了, 所以这里异步执行以下可以跳出锁, 可以保证刷新行为会是同步执行的.
        queue.async {
            self.authenticator.refresh(credential, for: session) { result in
                // 刷新完成回调
                self.$mutableState.write { mutableState in
                    switch result {
                    case let .success(credential):
                        // 成功处理
                        self.handleRefreshSuccess(credential, insideLock: &mutableState)
                    case let .failure(error):
                        self.handleRefreshFailure(error, insideLock: &mutableState)
                    }
                }
            }
        }
    }
    // 检测是否超出最大刷新次数
    private func isRefreshExcessive(insideLock mutableState: inout MutableState) -> Bool {
        // 先获取时间窗口对象, 没有的话表示没有限制最大次数
        guard let refreshWindow = mutableState.refreshWindow else { return false }
        // 时间窗口最小值的时间戳
        let refreshWindowMin = ProcessInfo.processInfo.systemUptime - refreshWindow.interval
        // 遍历保存的刷新时间戳, 使用reduce 计算下窗口内刷新的次数
        let refreshAttemptsWithinWindow = mutableState.refreshTimestamps.reduce(into: 0) { attempts, refreshTimestamp in
            guard refreshWindowMin <= refreshTimestamp else { return }
            attempts += 1
        }
        // 是否超过最大刷新次数了
        let isRefreshExcessive = refreshAttemptsWithinWindow >= refreshWindow.maximumAttempts

        return isRefreshExcessive
    }
    // 处理刷新成功
    private func handleRefreshSuccess(_ credential: Credential, insideLock mutableState: inout MutableState) {
        // 取出暂存的适配请求的参数数组
        mutableState.credential = credential
        
        // 取出暂存的适配请求的参数数组
        let adaptOperations = mutableState.adaptOperations
        // 取出暂存的重试回调数组
        let requestsToRetry = mutableState.requestsToRetry
        // 把self 持有的暂存数据清空
        mutableState.adaptOperations.removeAll()
        mutableState.requestsToRetry.removeAll()
        // 关闭刷新中的状态
        mutableState.isRefreshing = false

        // Dispatch to queue to hop out of the mutable state lock
        // 在queue中异步执行来跳出锁
        queue.async {
            adaptOperations.forEach { self.adapt($0.urlRequest, for: $0.session, completion: $0.completion) }
            requestsToRetry.forEach { $0(.retry) }
        }
    }
    // 处理刷新失败
    private func handleRefreshFailure(_ error: Error, insideLock mutableState: inout MutableState) {
        // 取出暂存的两个数组
        let adaptOperations = mutableState.adaptOperations
        let requestsToRetry = mutableState.requestsToRetry
        // 清空self持有的暂存数组
        mutableState.adaptOperations.removeAll()
        mutableState.requestsToRetry.removeAll()
        // 关闭刷新中状态
        mutableState.isRefreshing = false

        // Dispatch to queue to hop out of the mutable state lock
        // 在queue 中异步执行来跳出锁
        queue.async {
            // 配器挨个调用失败
            adaptOperations.forEach { $0.completion(.failure(error)) }
            // 重试器也挨个调用失败
            requestsToRetry.forEach { $0(.doNotRetryWithError(error)) }
        }
    }
}
