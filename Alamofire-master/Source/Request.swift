//
//  Request.swift
//
//  Copyright (c) 2014-2020 Alamofire Software Foundation (http://alamofire.org/)
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

/// `Request` is the common superclass of all Alamofire request types and provides common state, delegate, and callback
/// handling.
/// Request 基类, 不直接使用, 使用派生类
/// 对外都是Request 对象, 先进行类型判断
public class Request {
    /// State of the `Request`, with managed transitions between states set when calling `resume()`, `suspend()`, or
    /// `cancel()` on the `Request`.
    ///
    public enum State {
        /// Initial state of the `Request`.
        case initialized // Request 初始状态
        /// `State` set when `resume()` is called. Any tasks created for the `Request` will have `resume()` called on
        /// them in this state.
        case resumed // 调用resumed 时候更新为该状态, 同事对所有自己创建的task 调用resume() 方法
        /// `State` set when `suspend()` is called. Any tasks created for the `Request` will have `suspend()` called on
        /// them in this state.
        case suspended // 类似resumed
        /// `State` set when `cancel()` is called. Any tasks created for the `Request` will have `cancel()` called on
        /// them. Unlike `resumed` or `suspended`, once in the `cancelled` state, the `Request` can no longer transition
        /// to any other state.
        case cancelled // 调用之后, Request 不能再转变为其他状态
        /// `State` set when all response serialization completion closures have been cleared on the `Request` and
        /// enqueued on their respective queues.
        case finished // 解析全部完成, 并且回调呗清除后更新为该状态

        /// Determines whether `self` can be transitioned to the provided `State`.
        /// 判断当前状态是否能转化为新的状态
        func canTransitionTo(_ state: State) -> Bool {
            switch (self, state) {
            case (.initialized, _):
                return true // 初始状态key变换任何状态
            case (_, .initialized), (.cancelled, _), (.finished, _):
                return false // 任何状态不能转化为初始状态, 取消完成 不能转为其他状态
            case (.resumed, .cancelled), (.suspended, .cancelled), (.resumed, .suspended), (.suspended, .resumed):
                return true // 可以相互转换的状态
            case (.suspended, .suspended), (.resumed, .resumed):
                return false // 挂起, 继续不能装为自身
            case (_, .finished):
                return true // 任何状态, 可以直接转为完成, cancel, finish 不可
            }
        }
    }

    // MARK: - Initial State

    /// `UUID` providing a unique identifier for the `Request`, used in the `Hashable` and `Equatable` conformances.
    /// 唯一id, 用来实现Hashable 以及Equatable 协议
    public let id: UUID
    /// The serial queue for all internal async actions.
    /// 内部异步操作执行队列
    public let underlyingQueue: DispatchQueue
    /// The queue used for all serialization actions. By default it's a serial queue that targets `underlyingQueue`.
    /// 响应解析的队列, 默认underlyingQueue
    public let serializationQueue: DispatchQueue
    /// `EventMonitor` used for event callbacks.
    /// 事件监听器
    public let eventMonitor: EventMonitor?
    /// The `Request`'s interceptor.
    /// 请求拦截器
    public let interceptor: RequestInterceptor?
    /// The `Request`'s delegate.
    /// 指向Session
    public private(set) weak var delegate: RequestDelegate?

    // MARK: - Mutable State

    /// Type encapsulating all mutable state that may need to be accessed from anything other than the `underlyingQueue`.
    /// 包括各种需要线程安全的属性
    struct MutableState {
        /// State of the `Request`.
        /// Request 状态
        var state: State = .initialized
        /// `ProgressHandler` and `DispatchQueue` provided for upload progress callbacks.
        /// 上传进度回调, 以及该回调所调用队列
        var uploadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)?
        /// `ProgressHandler` and `DispatchQueue` provided for download progress callbacks.
        /// 现在进度回调和队列
        var downloadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)?
        /// `RedirectHandler` provided for to handle request redirection.
        /// 重定向处理协议对象
        var redirectHandler: RedirectHandler?
        /// `CachedResponseHandler` provided to handle response caching.
        /// 缓存处理协议对象
        var cachedResponseHandler: CachedResponseHandler?
        /// Queue and closure called when the `Request` is able to create a cURL description of itself.
        /// 当Request 创建curl 时, 该属性持有创建curl 的回调以及调用队列
        var cURLHandler: (queue: DispatchQueue, handler: (String) -> Void)?
        /// Queue and closure called when the `Request` creates a `URLRequest`.
        /// Request 创建URLRequest 成功后回调以及队列
        var urlRequestHandler: (queue: DispatchQueue, handler: (URLRequest) -> Void)?
        /// Queue and closure called when the `Request` creates a `URLSessionTask`.
        /// Request 创建Task 成功回调及队列
        var urlSessionTaskHandler: (queue: DispatchQueue, handler: (URLSessionTask) -> Void)?
        /// Response serialization closures that handle response parsing.
        /// 响应解析回调数组
        var responseSerializers: [() -> Void] = []
        /// Response serialization completion closures executed once all response serializers are complete.
        /// 响应解析完成回调数组
        var responseSerializerCompletions: [() -> Void] = []
        /// Whether response serializer processing is finished.
        /// 解析是否完成
        var responseSerializerProcessingFinished = false
        /// `URLCredential` used for authentication challenges.
        /// http 请求认证证书
        var credential: URLCredential?
        /// All `URLRequest`s created by Alamofire on behalf of the `Request`.
        /// 所有被Request 对象创建的URLRequest 对象数组
        var requests: [URLRequest] = []
        /// All `URLSessionTask`s created by Alamofire on behalf of the `Request`.
        /// 所有被Request 对象创建的URLSessionTask 对象数组
        var tasks: [URLSessionTask] = []
        /// All `URLSessionTaskMetrics` values gathered by Alamofire on behalf of the `Request`. Should correspond
        /// exactly the the `tasks` created.
        /// 所有Task 数组对象的请求指标
        var metrics: [URLSessionTaskMetrics] = []
        /// Number of times any retriers provided retried the `Request`.
        /// 当前重试次数
        var retryCount = 0
        /// Final `AFError` for the `Request`, whether from various internal Alamofire calls or as a result of a `task`.
        /// 最终抛出错误
        var error: AFError?
        /// Whether the instance has had `finish()` called and is running the serializers. Should be replaced with a
        /// representation in the state machine in the future.
        /// 是否调用finished 方法, 跟State 中的finished 一致
        var isFinishing = false
        /// Actions to run when requests are finished. Use for concurrency support.
        /// 完成回调
        var finishHandlers: [() -> Void] = []
    }

    /// Protected `MutableState` value that provides thread-safe access to state values.
    /// 属性包装器, 保证现场安全, 后面几个计算属性, 从这个里面取值
    @Protected
    fileprivate var mutableState = MutableState()

    /// `State` of the `Request`.
    /// 几个判断计算属性
    public var state: State { $mutableState.state }
    /// Returns whether `state` is `.initialized`.
    public var isInitialized: Bool { state == .initialized }
    /// Returns whether `state is `.resumed`.
    public var isResumed: Bool { state == .resumed }
    /// Returns whether `state` is `.suspended`.
    public var isSuspended: Bool { state == .suspended }
    /// Returns whether `state` is `.cancelled`.
    public var isCancelled: Bool { state == .cancelled }
    /// Returns whether `state` is `.finished`.
    public var isFinished: Bool { state == .finished }

    // MARK: Progress

    /// Closure type executed when monitoring the upload or download progress of a request.
    /// 监听器监听进度时的回调类型
    public typealias ProgressHandler = (Progress) -> Void

    /// `Progress` of the upload of the body of the executed `URLRequest`. Reset to `0` if the `Request` is retried.
    /// 上传进度, retry 时会被还原成0
    public let uploadProgress = Progress(totalUnitCount: 0)
    /// `Progress` of the download of any response data. Reset to `0` if the `Request` is retried.
    /// 下载进度, retry 时会被还原成0
    public let downloadProgress = Progress(totalUnitCount: 0)
    /// `ProgressHandler` called when `uploadProgress` is updated, on the provided `DispatchQueue`.
    /// 线程安全的上传进度回调和调用的queue
    private var uploadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)? {
        get { $mutableState.uploadProgressHandler }
        set { $mutableState.uploadProgressHandler = newValue }
    }

    /// `ProgressHandler` called when `downloadProgress` is updated, on the provided `DispatchQueue`.
    /// 线程安全的下载进度回调和调用的queue
    fileprivate var downloadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)? {
        get { $mutableState.downloadProgressHandler }
        set { $mutableState.downloadProgressHandler = newValue }
    }

    // MARK: Redirect Handling

    /// `RedirectHandler` set on the instance.
    /// 线程安全的重定向处理协议对象
    public private(set) var redirectHandler: RedirectHandler? {
        get { $mutableState.redirectHandler }
        set { $mutableState.redirectHandler = newValue }
    }

    // MARK: Cached Response Handling

    /// `CachedResponseHandler` set on the instance.
    /// 线程安全的处理缓存协议对象
    public private(set) var cachedResponseHandler: CachedResponseHandler? {
        get { $mutableState.cachedResponseHandler }
        set { $mutableState.cachedResponseHandler = newValue }
    }

    // MARK: URLCredential

    /// `URLCredential` used for authentication challenges. Created by calling one of the `authenticate` methods.
    /// 线程安全的证书对象, 在调用authenticate 相关方法时候创建
    public private(set) var credential: URLCredential? {
        get { $mutableState.credential }
        set { $mutableState.credential = newValue }
    }

    // MARK: Validators

    /// `Validator` callback closures that store the validation calls enqueued.
    /// 保存使用validation 来进行有效性校验的闭包
    @Protected
    fileprivate var validators: [() -> Void] = []

    // MARK: URLRequests

    /// All `URLRequests` created on behalf of the `Request`, including original and adapted requests.
    /// 线程安全的URLRequest 数组, 包括原始URLRequest 以及适配器处理过的URLRequest
    public var requests: [URLRequest] { $mutableState.requests }
    /// First `URLRequest` created on behalf of the `Request`. May not be the first one actually executed.
    /// 第一个创建的URLRequest, 可能并不是第一个发出去的请求
    public var firstRequest: URLRequest? { requests.first }
    /// Last `URLRequest` created on behalf of the `Request`.
    /// 最后一个创建的URLRequest
    public var lastRequest: URLRequest? { requests.last }
    /// Current `URLRequest` created on behalf of the `Request`.
    /// 当前URLRequest 当前最后一个
    public var request: URLRequest? { lastRequest }

    /// `URLRequest`s from all of the `URLSessionTask`s executed on behalf of the `Request`. May be different from
    /// `requests` due to `URLSession` manipulation.
    /// 创建的URLSessionTask 的URLRequest 数组, 可能跟requests 属性不一样, 因为requests 包括了原始请求以及适配器处理过的请求
    public var performedRequests: [URLRequest] { $mutableState.read { $0.tasks.compactMap(\.currentRequest) } }

    // MARK: HTTPURLResponse

    /// `HTTPURLResponse` received from the server, if any. If the `Request` was retried, this is the response of the
    /// last `URLSessionTask`.
    /// 服务器返回的响应, 若果请求重试, 该属性为最后的task 响应
    public var response: HTTPURLResponse? { lastTask?.response as? HTTPURLResponse }

    // MARK: Tasks

    /// All `URLSessionTask`s created on behalf of the `Request`.
    /// 线程安全的task 数组
    public var tasks: [URLSessionTask] { $mutableState.tasks }
    /// First `URLSessionTask` created on behalf of the `Request`.
    /// 第一个创建的task
    public var firstTask: URLSessionTask? { tasks.first }
    /// Last `URLSessionTask` crated on behalf of the `Request`.
    /// 最后一个创建的task
    public var lastTask: URLSessionTask? { tasks.last }
    /// Current `URLSessionTask` created on behalf of the `Request`.
    /// 当前task, 当前最后一个创建的task
    public var task: URLSessionTask? { lastTask }

    // MARK: Metrics

    /// All `URLSessionTaskMetrics` gathered on behalf of the `Request`. Should correspond to the `tasks` created.
    /// 线程安全的请求指标数组
    public var allMetrics: [URLSessionTaskMetrics] { $mutableState.metrics }
    /// First `URLSessionTaskMetrics` gathered on behalf of the `Request`.
    /// 第一个请求到的
    public var firstMetrics: URLSessionTaskMetrics? { allMetrics.first }
    /// Last `URLSessionTaskMetrics` gathered on behalf of the `Request`.
    /// 最后一个请求到的
    public var lastMetrics: URLSessionTaskMetrics? { allMetrics.last }
    /// Current `URLSessionTaskMetrics` gathered on behalf of the `Request`.
    /// 当前请求指标, 当前最后一个请求到的指标
    public var metrics: URLSessionTaskMetrics? { lastMetrics }

    // MARK: Retry Count

    /// Number of times the `Request` has been retried.
    /// 已经重试过的次数
    public var retryCount: Int { $mutableState.retryCount }

    // MARK: Error

    /// `Error` returned from Alamofire internally, from the network request directly, or any validators executed.
    /// 线程安全的抛出错误
    public fileprivate(set) var error: AFError? {
        get { $mutableState.error }
        set { $mutableState.error = newValue }
    }

    /// Default initializer for the `Request` superclass.
    ///
    /// - Parameters:
    ///   - id:                 `UUID` used for the `Hashable` and `Equatable` implementations. `UUID()` by default.
    ///   - underlyingQueue:    `DispatchQueue` on which all internal `Request` work is performed.
    ///   - serializationQueue: `DispatchQueue` on which all serialization work is performed. By default targets
    ///                         `underlyingQueue`, but can be passed another queue from a `Session`.
    ///   - eventMonitor:       `EventMonitor` called for event callbacks from internal `Request` actions.
    ///   - interceptor:        `RequestInterceptor` used throughout the request lifecycle.
    ///   - delegate:           `RequestDelegate` that provides an interface to actions not performed by the `Request`.
    init(id: UUID = UUID(),
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: EventMonitor?,
         interceptor: RequestInterceptor?,
         delegate: RequestDelegate) {
        self.id = id
        self.underlyingQueue = underlyingQueue
        self.serializationQueue = serializationQueue
        self.eventMonitor = eventMonitor
        self.interceptor = interceptor
        self.delegate = delegate
    }

    // MARK: - Internal Event API
    // 内部api, 模块外不可用
    // 请求过程中的状态变化通知
    // 都是在underlyingQueue 队列中执行
    // All API must be called from underlyingQueue.

    /// Called when an initial `URLRequest` has been created on behalf of the instance. If a `RequestAdapter` is active,
    /// the `URLRequest` will be adapted before being issued.
    ///
    /// - Parameter request: The `URLRequest` created.
    /// 原始URLRequest 对象呗创建成功后调用, Session 中调用
    func didCreateInitialURLRequest(_ request: URLRequest) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 添加到requests 数组
        $mutableState.write { $0.requests.append(request) }
        // 通知监听器
        eventMonitor?.request(self, didCreateInitialURLRequest: request)
    }

    /// Called when initial `URLRequest` creation has failed, typically through a `URLRequestConvertible`.
    ///
    /// - Note: Triggers retry.
    ///
    /// - Parameter error: `AFError` thrown from the failed creation.
    /// 创建原始URLRequest 对象失败时调用, session 调用
    func didFailToCreateURLRequest(with error: AFError) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 记录错误
        self.error = error
        // 通知监听器
        eventMonitor?.request(self, didFailToCreateURLRequestWithError: error)
        // 调用下curl 回调, 在创建request 完成前设置了curl 回调, 会把回调存起来, 这时候调用
        callCURLHandlerIfNecessary()
        // 重试或者抛出错误
        retryOrFinish(error: error)
    }

    /// Called when a `RequestAdapter` has successfully adapted a `URLRequest`.
    ///
    /// - Parameters:
    ///   - initialRequest: The `URLRequest` that was adapted.
    ///   - adaptedRequest: The `URLRequest` returned by the `RequestAdapter`.
    /// 适配器适配原始URLRequest 成功后回调, 参数为原始URLRequest 以及新的URLRequest(Session 中调用)
    func didAdaptInitialRequest(_ initialRequest: URLRequest, to adaptedRequest: URLRequest) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 添加到requests 数组
        $mutableState.write { $0.requests.append(adaptedRequest) }
        // 通知监听器
        eventMonitor?.request(self, didAdaptInitialRequest: initialRequest, to: adaptedRequest)
    }

    /// Called when a `RequestAdapter` fails to adapt a `URLRequest`.
    ///
    /// - Note: Triggers retry.
    ///
    /// - Parameters:
    ///   - request: The `URLRequest` the adapter was called with.
    ///   - error:   The `AFError` returned by the `RequestAdapter`.
    /// 适配器处理请求失败时调用, Session 调用
    func didFailToAdaptURLRequest(_ request: URLRequest, withError error: AFError) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        self.error = error

        eventMonitor?.request(self, didFailToAdaptURLRequest: request, withError: error)
        // 调用下curl 回调, 在创建request 完成前设置了curl 回调, 存起来, 调用
        callCURLHandlerIfNecessary()

        retryOrFinish(error: error)
    }

    /// Final `URLRequest` has been created for the instance.
    ///
    /// - Parameter request: The `URLRequest` created.
    /// 创建URLRequest 完成时调用, 适配器适配完成, 参数为适配器处理过后的Request 对象Session 调用
    func didCreateURLRequest(_ request: URLRequest) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        $mutableState.read { state in
            // 执行state 中的请求创建成功回调
            state.urlRequestHandler?.queue.async { state.urlRequestHandler?.handler(request) }
        }

        eventMonitor?.request(self, didCreateURLRequest: request)
        // 调用curl 回调
        callCURLHandlerIfNecessary()
    }

    /// Asynchronously calls any stored `cURLHandler` and then removes it from `mutableState`.
    /// 异步调用之前存的curl 回调, 然后删掉已经调用过的回调
    private func callCURLHandlerIfNecessary() {
        $mutableState.write { mutableState in
            guard let cURLHandler = mutableState.cURLHandler else { return }

            cURLHandler.queue.async { cURLHandler.handler(self.cURLDescription()) }

            mutableState.cURLHandler = nil
        }
    }

    /// Called when a `URLSessionTask` is created on behalf of the instance.
    ///
    /// - Parameter task: The `URLSessionTask` created.
    /// 创建URLSessionTask 成功后调用, 1. 直接创建task 成功, 2. 创建断点续传task 成功(Session 中调用)
    func didCreateTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 添加到tasks 数组, 然后调用state 里的创建task 成功回调
        $mutableState.write { state in
            state.tasks.append(task)

            guard let urlSessionTaskHandler = state.urlSessionTaskHandler else { return }

            urlSessionTaskHandler.queue.async { urlSessionTaskHandler.handler(task) }
        }

        eventMonitor?.request(self, didCreateTask: task)
    }

    /// Called when resumption is completed.
    /// 当Request 对象调用resume() 方法时调用, 自己调用, 外部调用request.resume() 方法
    func didResume() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 通知监听器
        eventMonitor?.requestDidResume(self)
    }

    /// Called when a `URLSessionTask` is resumed on behalf of the instance.
    ///
    /// - Parameter task: The `URLSessionTask` resumed.
    /// URLSessionTask 调用resume 后调用, 1. 自己调用resume() 方法会对task 调用resume 方法. 然后调用该方法. 2. Session 调用updateStatesForTask 方法来更新task 的状态时会调用该方法
    func didResumeTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.request(self, didResumeTask: task)
    }

    /// Called when suspension is completed.
    /// 调用suspend 方法后调用该方法 自己调用
    func didSuspend() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.requestDidSuspend(self)
    }

    /// Called when a `URLSessionTask` is suspended on behalf of the instance.
    ///
    /// - Parameter task: The `URLSessionTask` suspended.
    /// task 调用suspend 方法后调用, 1. 自己调用suspend() 方法会对task 调用suspend 方法. 然后调用该方法. 2. Session 调用updateStatesForTask 方法来更新task 的状态时会调用该方法
    func didSuspendTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.request(self, didSuspendTask: task)
    }

    /// Called when cancellation is completed, sets `error` to `AFError.explicitlyCancelled`.
    /// 调用cancel()方法后调用(1. 直接取消, 2.提供一个已下载的data后再取消), 若此时error为nil, 会把error设置为AFError.explicitlyCancelled
    func didCancel() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        error = error ?? AFError.explicitlyCancelled

        eventMonitor?.requestDidCancel(self)
    }

    /// Called when a `URLSessionTask` is cancelled on behalf of the instance.
    ///
    /// - Parameter task: The `URLSessionTask` cancelled.
    /// task调用cancel方法后调用(1. 自己调用cancel方法后会调用task的cancel方法, 然后调用该方法. 2.Session调用了updateStatesForTask方法来更新task的状态时会调用该方法)
    func didCancelTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.request(self, didCancelTask: task)
    }

    /// Called when a `URLSessionTaskMetrics` value is gathered on behalf of the instance.
    ///
    /// - Parameter metrics: The `URLSessionTaskMetrics` gathered.
    /// task 成功请求到请求指标后调用(SessionDelegate中通过stateProvider(Session)调用)
    func didGatherMetrics(_ metrics: URLSessionTaskMetrics) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        $mutableState.write { $0.metrics.append(metrics) }

        eventMonitor?.request(self, didGatherMetrics: metrics)
    }

    /// Called when a `URLSessionTask` fails before it is finished, typically during certificate pinning.
    ///
    /// - Parameters:
    ///   - task:  The `URLSessionTask` which failed.
    ///   - error: The early failure `AFError`.
    /// task 在请求完成前失败了(比如认证失败)调用(SessionDelegate中使用stateProvider(Session)调用)
    func didFailTask(_ task: URLSessionTask, earlyWithError error: AFError) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        self.error = error

        // Task will still complete, so didCompleteTask(_:with:) will handle retry.
        eventMonitor?.request(self, didFailTask: task, earlyWithError: error)
    }

    /// Called when a `URLSessionTask` completes. All tasks will eventually call this method.
    ///
    /// - Note: Response validation is synchronously triggered in this step.
    ///
    /// - Parameters:
    ///   - task:  The `URLSessionTask` which completed.
    ///   - error: The `AFError` `task` may have completed with. If `error` has already been set on the instance, this
    ///            value is ignored.
    /// task 请求完成后调用(所有task 都会调用这个方法,不管成功与否)(在SessionDelegate 中使用stateProvider(Session) 调用)
    func didCompleteTask(_ task: URLSessionTask, with error: AFError?) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        self.error = self.error ?? error

        validators.forEach { $0() }

        eventMonitor?.request(self, didCompleteTask: task, with: error)

        retryOrFinish(error: self.error)
    }

    /// Called when the `RequestDelegate` is going to retry this `Request`. Calls `reset()`.
    /// 准备重试时调用(自己调用retryRequest 时调用)
    func prepareForRetry() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 重试次数 +1
        $mutableState.write { $0.retryCount += 1 }
        // 还原状态
        reset()

        eventMonitor?.requestIsRetrying(self)
    }

    /// Called to determine whether retry will be triggered for the particular error, or whether the instance should
    /// call `finish()`.
    ///
    /// - Parameter error: The possible `AFError` which may trigger retry.
    /// 决定是重试还是完成(自己调用)
    func retryOrFinish(error: AFError?) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 如果没错误或者没有代理对象, 直接调用finish()
        guard let error = error, let delegate = delegate else { finish(); return }
        // 否则询问代理是否有重试逻辑
        delegate.retryResult(for: self, dueTo: error) { retryResult in
            switch retryResult {
            case .doNotRetry: // 不重试, 直接finish
                self.finish()
            case let .doNotRetryWithError(retryError): // 不重试, 抛出错误
                self.finish(error: retryError.asAFError(orFailWith: "Received retryError was not already AFError"))
            case .retry, .retryWithDelay: // 重试或者延迟重试
                delegate.retryRequest(self, withDelay: retryResult.delay)
            }
        }
    }

    /// Finishes this `Request` and starts the response serializers.
    ///
    /// - Parameter error: The possible `Error` with which the instance will finish.
    /// 请求完成时的操作(1. 自己调用. 2.Session deinit时对所有Request 调用AFError.sessionDeinitialized, Session失效时对所有请求调用AFError.sessionInvalidated)
    func finish(error: AFError? = nil) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))
        // 如果请求已经完成了, 忽略
        guard !$mutableState.isFinishing else { return }
        // 标记为完成
        $mutableState.isFinishing = true
        // 有错误的话, 记录
        if let error = error { self.error = error }

        // Start response handlers
        // 开始执行响应解析
        processNextResponseSerializer()

        eventMonitor?.requestDidFinish(self)
    }

    /// Appends the response serialization closure to the instance.
    ///
    ///  - Note: This method will also `resume` the instance if `delegate.startImmediately` returns `true`.
    ///
    /// - Parameter closure: The closure containing the response serialization call.
    /// 线程安全地添加响应解析回调
    func appendResponseSerializer(_ closure: @escaping () -> Void) {
        $mutableState.write { mutableState in
            // 加入数组
            mutableState.responseSerializers.append(closure)
            // 如果请求完成了,标记为继续
            if mutableState.state == .finished {
                mutableState.state = .resumed
            }
            // 如果响应解析完成了, 调一下解析方法
            if mutableState.responseSerializerProcessingFinished {
                underlyingQueue.async { self.processNextResponseSerializer() }
            }
            // 如果不是完成状态, 且可以转换为继续状态
            if mutableState.state.canTransitionTo(.resumed) {
                // 问问Session 是否需要立刻开始, 是的话就立刻调用resume()
                underlyingQueue.async { if self.delegate?.startImmediately == true { self.resume() } }
            }
        }
    }

    /// Returns the next response serializer closure to execute if there's one left.
    ///
    /// - Returns: The next response serialization closure, if there is one.
    /// 线程安全地获取下一个响应解析回调
    func nextResponseSerializer() -> (() -> Void)? {
        var responseSerializer: (() -> Void)?

        $mutableState.write { mutableState in
            // 已经完成的解析回调个数
            let responseSerializerIndex = mutableState.responseSerializerCompletions.count
            // 看看完成的个数是否等于存在的解析回调个数
            if responseSerializerIndex < mutableState.responseSerializers.count {
                responseSerializer = mutableState.responseSerializers[responseSerializerIndex]
            }
        }

        return responseSerializer
    }

    /// Processes the next response serializer and calls all completions if response serialization is complete.
    /// 开始处理下一个响应解析器, 如果全部解析器都处理完了, 更新状态为finish(自己调用:1.task请求完成后会调用finish()时调用该方法, 2.添加新的解析回调之后会调用该方法, 3.解析完全部响应之后会调用)
    func processNextResponseSerializer() {
        guard let responseSerializer = nextResponseSerializer() else {
            // Execute all response serializer completions and clear them
            // 解析器处理完的话就调用全部的解析处理完成回调并删除
            var completions: [() -> Void] = []
            
            $mutableState.write { mutableState in
                // 先存一下完成回调数组
                completions = mutableState.responseSerializerCompletions

                // Clear out all response serializers and response serializer completions in mutable state since the
                // request is complete. It's important to do this prior to calling the completion closures in case
                // the completions call back into the request triggering a re-processing of the response serializers.
                // An example of how this can happen is by calling cancel inside a response completion closure.
                // 然后先清空解析回调数组,以及完成回调数组, 避免回调数组中调用了cancel方法, 导致循环调用
                mutableState.responseSerializers.removeAll()
                mutableState.responseSerializerCompletions.removeAll()
                // 标记为完成
                if mutableState.state.canTransitionTo(.finished) {
                    mutableState.state = .finished
                }
                // 标记响应解析完成
                mutableState.responseSerializerProcessingFinished = true
                mutableState.isFinishing = false
            }
            // 执行完成回调
            completions.forEach { $0() }

            // Cleanup the request
            // 清除请求状态
            cleanup()

            return
        }
        // 如果还有响应解析回调, 调用
        serializationQueue.async { responseSerializer() }
    }

    /// Notifies the `Request` that the response serializer is complete.
    ///
    /// - Parameter completion: The completion handler provided with the response serializer, called when all serializers
    ///                         are complete.
    /// 通知Request 全部的响应解析完成了
    func responseSerializerDidComplete(completion: @escaping () -> Void) {
        // 先把完成回调加入到数组
        $mutableState.write { $0.responseSerializerCompletions.append(completion) }
        // 然后执行下一个响应解析, 如果没有解析了就会挨个调用完成回调
        processNextResponseSerializer()
    }

    /// Resets all task and response serializer related state for retry.
    /// 重置请求状态
    func reset() {
        error = nil

        uploadProgress.totalUnitCount = 0
        uploadProgress.completedUnitCount = 0
        downloadProgress.totalUnitCount = 0
        downloadProgress.completedUnitCount = 0

        $mutableState.write { state in
            state.isFinishing = false
            state.responseSerializerCompletions = []
        }
    }

    /// Called when updating the upload progress.
    ///
    /// - Parameters:
    ///   - totalBytesSent: Total bytes sent so far.
    ///   - totalBytesExpectedToSend: Total bytes expected to send.
    /// 更新上传进度
    func updateUploadProgress(totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        uploadProgress.totalUnitCount = totalBytesExpectedToSend
        uploadProgress.completedUnitCount = totalBytesSent

        uploadProgressHandler?.queue.async { self.uploadProgressHandler?.handler(self.uploadProgress) }
    }

    /// Perform a closure on the current `state` while locked.
    ///
    /// - Parameter perform: The closure to perform.
    /// 线程安全的操作state 属性
    func withState(perform: (State) -> Void) {
        $mutableState.withState(perform: perform)
    }

    // MARK: Task Creation

    /// Called when creating a `URLSessionTask` for this `Request`. Subclasses must override.
    ///
    /// - Parameters:
    ///   - request: `URLRequest` to use to create the `URLSessionTask`.
    ///   - session: `URLSession` which creates the `URLSessionTask`.
    ///
    /// - Returns:   The `URLSessionTask` created.
    /// 给Request 创建URLSessionTask 时, Session 会调用该方法取得创建的URLSessionTask, 几个子类各自实现
    func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        fatalError("Subclasses must override.")
    }

    // MARK: - Public API
    // 开放api, 可以被模块外部调用
    // These APIs are callable from any queue.

    // MARK: State

    /// Cancels the instance. Once cancelled, a `Request` can no longer be resumed or suspended.
    ///
    /// - Returns: The instance.
    /// 取消Request, 一旦取消了, 就再也不能继续跟挂起了
    @discardableResult
    public func cancel() -> Self {
        $mutableState.write { mutableState in
            // 检测是否能取消请求
            guard mutableState.state.canTransitionTo(.cancelled) else { return }
            // 设置状态
            mutableState.state = .cancelled
            // 通知调用取消完成
            underlyingQueue.async { self.didCancel() }
            // 最后一个task 是否完成了
            guard let task = mutableState.tasks.last, task.state != .completed else {
                // 最后一个task如果完成了, 代表请求完成, 直接走finish逻辑
                underlyingQueue.async { self.finish() }
                return
            }

            // Resume to ensure metrics are gathered.
            // 先恢复一下task 确保请求指标被获取了
            task.resume()
            // 取消task
            task.cancel()
            // 通知task取消完成
            underlyingQueue.async { self.didCancelTask(task) }
        }

        return self
    }

    /// Suspends the instance.
    ///
    /// - Returns: The instance.
    /// 挂起请求
    @discardableResult
    public func suspend() -> Self {
        $mutableState.write { mutableState in
            // 检测是否能挂起
            guard mutableState.state.canTransitionTo(.suspended) else { return }
            // 更新状态
            mutableState.state = .suspended
            // 通知调用suspend()完成
            underlyingQueue.async { self.didSuspend() }
            // 检测最后一个请求是否完成, 完成的话跳过
            guard let task = mutableState.tasks.last, task.state != .completed else { return }
            // 挂起task
            task.suspend()
            // 通知task挂起完成
            underlyingQueue.async { self.didSuspendTask(task) }
        }

        return self
    }

    /// Resumes the instance.
    ///
    /// - Returns: The instance.
    /// 继续task
    @discardableResult
    public func resume() -> Self {
        $mutableState.write { mutableState in
            // 检查能否继续
            guard mutableState.state.canTransitionTo(.resumed) else { return }

            mutableState.state = .resumed

            underlyingQueue.async { self.didResume() }
            // 检测task 是否全部完成
            guard let task = mutableState.tasks.last, task.state != .completed else { return }
            // 继续task
            task.resume()
            // 通知task继续完成
            underlyingQueue.async { self.didResumeTask(task) }
        }

        return self
    }

    // MARK: - Closure API

    /// Associates a credential using the provided values with the instance.
    ///
    /// - Parameters:
    ///   - username:    The username.
    ///   - password:    The password.
    ///   - persistence: The `URLCredential.Persistence` for the created `URLCredential`. `.forSession` by default.
    ///
    /// - Returns:       The instance.
    /// http认证
    @discardableResult
    public func authenticate(username: String, password: String, persistence: URLCredential.Persistence = .forSession) -> Self {
        let credential = URLCredential(user: username, password: password, persistence: persistence)

        return authenticate(with: credential)
    }

    /// Associates the provided credential with the instance.
    ///
    /// - Parameter credential: The `URLCredential`.
    ///
    /// - Returns:              The instance.
    /// http认证
    @discardableResult
    public func authenticate(with credential: URLCredential) -> Self {
        $mutableState.credential = credential

        return self
    }

    /// Sets a closure to be called periodically during the lifecycle of the instance as data is read from the server.
    ///
    /// - Note: Only the last closure provided is used.
    ///
    /// - Parameters:
    ///   - queue:   The `DispatchQueue` to execute the closure on. `.main` by default.
    ///   - closure: The closure to be executed periodically as data is read from the server.
    ///
    /// - Returns:   The instance.
    /// 设置下载进度回调以及队列, 注意只有最后设置的回调有效
    @discardableResult
    public func downloadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler) -> Self {
        $mutableState.downloadProgressHandler = (handler: closure, queue: queue)

        return self
    }

    /// Sets a closure to be called periodically during the lifecycle of the instance as data is sent to the server.
    ///
    /// - Note: Only the last closure provided is used.
    ///
    /// - Parameters:
    ///   - queue:   The `DispatchQueue` to execute the closure on. `.main` by default.
    ///   - closure: The closure to be executed periodically as data is sent to the server.
    ///
    /// - Returns:   The instance.
    /// 设置上传进度回调以及队列, 只有最后设置的回调有效
    @discardableResult
    public func uploadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler) -> Self {
        $mutableState.uploadProgressHandler = (handler: closure, queue: queue)

        return self
    }

    // MARK: Redirects

    /// Sets the redirect handler for the instance which will be used if a redirect response is encountered.
    ///
    /// - Note: Attempting to set the redirect handler more than once is a logic error and will crash.
    ///
    /// - Parameter handler: The `RedirectHandler`.
    ///
    /// - Returns:           The instance.
    /// 设置重定向协议对象, 只允许设置一次
    @discardableResult
    public func redirect(using handler: RedirectHandler) -> Self {
        $mutableState.write { mutableState in
            precondition(mutableState.redirectHandler == nil, "Redirect handler has already been set.")
            mutableState.redirectHandler = handler
        }

        return self
    }

    // MARK: Cached Responses

    /// Sets the cached response handler for the `Request` which will be used when attempting to cache a response.
    ///
    /// - Note: Attempting to set the cache handler more than once is a logic error and will crash.
    ///
    /// - Parameter handler: The `CachedResponseHandler`.
    ///
    /// - Returns:           The instance.
    /// 设置缓存处理协议对象, 只允许设置一次
    @discardableResult
    public func cacheResponse(using handler: CachedResponseHandler) -> Self {
        $mutableState.write { mutableState in
            precondition(mutableState.cachedResponseHandler == nil, "Cached response handler has already been set.")
            mutableState.cachedResponseHandler = handler
        }

        return self
    }

    // MARK: - Lifetime APIs

    /// Sets a handler to be called when the cURL description of the request is available.
    ///
    /// - Note: When waiting for a `Request`'s `URLRequest` to be created, only the last `handler` will be called.
    ///
    /// - Parameters:
    ///   - queue:   `DispatchQueue` on which `handler` will be called.
    ///   - handler: Closure to be called when the cURL description is available.
    ///
    /// - Returns:           The instance.
    /// 设置curl 描述, 以及调用队列, 当urlrequest 还未创建好时, 会保存最后一个设置的回调, 在urlrequest 创建完成或者失败后调用, 当urlrequest 已经创建完成后, 设置curl 描述调用会直接调用
    @discardableResult
    public func cURLDescription(on queue: DispatchQueue, calling handler: @escaping (String) -> Void) -> Self {
        $mutableState.write { mutableState in
            // 已经创建了urlrequest, 直接调用
            if mutableState.requests.last != nil {
                queue.async { handler(self.cURLDescription()) }
            } else {
                // 尚未创建urlrequest, 保存回调
                mutableState.cURLHandler = (queue, handler)
            }
        }

        return self
    }

    /// Sets a handler to be called when the cURL description of the request is available.
    ///
    /// - Note: When waiting for a `Request`'s `URLRequest` to be created, only the last `handler` will be called.
    ///
    /// - Parameter handler: Closure to be called when the cURL description is available. Called on the instance's
    ///                      `underlyingQueue` by default.
    ///
    /// - Returns:           The instance.
    /// 跟上面一样, 在underlyingQueue队列调用
    @discardableResult
    public func cURLDescription(calling handler: @escaping (String) -> Void) -> Self {
        $mutableState.write { mutableState in
            if mutableState.requests.last != nil {
                underlyingQueue.async { handler(self.cURLDescription()) }
            } else {
                mutableState.cURLHandler = (underlyingQueue, handler)
            }
        }

        return self
    }

    /// Sets a closure to called whenever Alamofire creates a `URLRequest` for this instance.
    ///
    /// - Note: This closure will be called multiple times if the instance adapts incoming `URLRequest`s or is retried.
    ///
    /// - Parameters:
    ///   - queue:   `DispatchQueue` on which `handler` will be called. `.main` by default.
    ///   - handler: Closure to be called when a `URLRequest` is available.
    ///
    /// - Returns:   The instance.
    ///
    /// 设置URLRequest 创建成功后的回调以及队列, 注意: 1. 如果有适配器或者请求重试, 回调会被调用多次, 2. 只会保存一个回调
    @discardableResult
    public func onURLRequestCreation(on queue: DispatchQueue = .main, perform handler: @escaping (URLRequest) -> Void) -> Self {
        $mutableState.write { state in
            if let request = state.requests.last {
                queue.async { handler(request) }
            }

            state.urlRequestHandler = (queue, handler)
        }

        return self
    }

    /// Sets a closure to be called whenever the instance creates a `URLSessionTask`.
    ///
    /// - Note: This API should only be used to provide `URLSessionTask`s to existing API, like `NSFileProvider`. It
    ///         **SHOULD NOT** be used to interact with tasks directly, as that may be break Alamofire features.
    ///         Additionally, this closure may be called multiple times if the instance is retried.
    ///
    /// - Parameters:
    ///   - queue:   `DispatchQueue` on which `handler` will be called. `.main` by default.
    ///   - handler: Closure to be called when the `URLSessionTask` is available.
    ///
    /// - Returns:   The instance.
    ///
    /// 设置URLSessionTask 创建完成的回调及其队列, 注意: 1.该方法不允许用来与URLSessionTask 交互, 否则会影响Alamofire 内部逻辑, 2. 如果请求会重试, 回调可能会被调用多次
    @discardableResult
    public func onURLSessionTaskCreation(on queue: DispatchQueue = .main, perform handler: @escaping (URLSessionTask) -> Void) -> Self {
        $mutableState.write { state in
            if let task = state.tasks.last {
                queue.async { handler(task) }
            }

            state.urlSessionTaskHandler = (queue, handler)
        }

        return self
    }

    // MARK: Cleanup

    /// Adds a `finishHandler` closure to be called when the request completes.
    ///
    /// - Parameter closure: Closure to be called when the request finishes.
    /// 完成后的回调
    func onFinish(perform finishHandler: @escaping () -> Void) {
        guard !isFinished else { finishHandler(); return }

        $mutableState.write { state in
            state.finishHandlers.append(finishHandler)
        }
    }

    /// Final cleanup step executed when the instance finishes response serialization.
    /// 清理内存, 子类各自实现来清理自己的数据
    func cleanup() {
        delegate?.cleanup(after: self)
        let handlers = $mutableState.finishHandlers
        handlers.forEach { $0() }
        $mutableState.write { state in
            state.finishHandlers.removeAll()
        }
    }
}

// MARK: - Protocol Conformances
// Request 扩展
extension Request: Equatable {
    // Equatable 协议用uuid 来比较
    public static func ==(lhs: Request, rhs: Request) -> Bool {
        lhs.id == rhs.id
    }
}

extension Request: Hashable {
    // Hashable 用uuid 做key
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Request: CustomStringConvertible {
    /// A textual representation of this instance, including the `HTTPMethod` and `URL` if the `URLRequest` has been
    /// created, as well as the response status code, if a response has been received.
    /// 对Request 对象的文本描述, 包括请求方法, url, 如果已经有响应数据, 会加上响应状态码
    public var description: String {
        // 啥都没有的话返回提示
        guard let request = performedRequests.last ?? lastRequest,
              let url = request.url,
              let method = request.httpMethod else { return "No request created yet." }

        let requestDescription = "\(method) \(url.absoluteString)"
        // map 函数可以对一个可选类型调用, 如果可选类型不为nil 的话, 调用回调, 把内容作为参数传入
        // 格式为: "请求方法 请求url 响应状态码"
        return response.map { "\(requestDescription) (\($0.statusCode))" } ?? requestDescription
    }
}
// 扩展Request, 返回请求的curl 格式(应该是linux 环境下调试用)
extension Request {
    /// cURL representation of the instance.
    ///
    /// - Returns: The cURL equivalent of the instance.
    public func cURLDescription() -> String {
        guard
            let request = lastRequest,
            let url = request.url,
            let host = url.host,
            let method = request.httpMethod else { return "$ curl command could not be created" }

        var components = ["$ curl -v"]

        components.append("-X \(method)")

        if let credentialStorage = delegate?.sessionConfiguration.urlCredentialStorage {
            let protectionSpace = URLProtectionSpace(host: host,
                                                     port: url.port ?? 0,
                                                     protocol: url.scheme,
                                                     realm: host,
                                                     authenticationMethod: NSURLAuthenticationMethodHTTPBasic)

            if let credentials = credentialStorage.credentials(for: protectionSpace)?.values {
                for credential in credentials {
                    guard let user = credential.user, let password = credential.password else { continue }
                    components.append("-u \(user):\(password)")
                }
            } else {
                if let credential = credential, let user = credential.user, let password = credential.password {
                    components.append("-u \(user):\(password)")
                }
            }
        }

        if let configuration = delegate?.sessionConfiguration, configuration.httpShouldSetCookies {
            if
                let cookieStorage = configuration.httpCookieStorage,
                let cookies = cookieStorage.cookies(for: url), !cookies.isEmpty {
                let allCookies = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: ";")

                components.append("-b \"\(allCookies)\"")
            }
        }

        var headers = HTTPHeaders()

        if let sessionHeaders = delegate?.sessionConfiguration.headers {
            for header in sessionHeaders where header.name != "Cookie" {
                headers[header.name] = header.value
            }
        }

        for header in request.headers where header.name != "Cookie" {
            headers[header.name] = header.value
        }

        for header in headers {
            let escapedValue = header.value.replacingOccurrences(of: "\"", with: "\\\"")
            components.append("-H \"\(header.name): \(escapedValue)\"")
        }

        if let httpBodyData = request.httpBody {
            let httpBody = String(decoding: httpBodyData, as: UTF8.self)
            var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
            escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")

            components.append("-d \"\(escapedBody)\"")
        }

        components.append("\"\(url.absoluteString)\"")

        return components.joined(separator: " \\\n\t")
    }
}

/// Protocol abstraction for `Request`'s communication back to the `SessionDelegate`.
public protocol RequestDelegate: AnyObject {
    /// `URLSessionConfiguration` used to create the underlying `URLSessionTask`s.
    var sessionConfiguration: URLSessionConfiguration { get }

    /// Determines whether the `Request` should automatically call `resume()` when adding the first response handler.
    var startImmediately: Bool { get }

    /// Notifies the delegate the `Request` has reached a point where it needs cleanup.
    ///
    /// - Parameter request: The `Request` to cleanup after.
    func cleanup(after request: Request)

    /// Asynchronously ask the delegate whether a `Request` will be retried.
    ///
    /// - Parameters:
    ///   - request:    `Request` which failed.
    ///   - error:      `Error` which produced the failure.
    ///   - completion: Closure taking the `RetryResult` for evaluation.
    func retryResult(for request: Request, dueTo error: AFError, completion: @escaping (RetryResult) -> Void)

    /// Asynchronously retry the `Request`.
    ///
    /// - Parameters:
    ///   - request:   `Request` which will be retried.
    ///   - timeDelay: `TimeInterval` after which the retry will be triggered.
    func retryRequest(_ request: Request, withDelay timeDelay: TimeInterval?)
}

// MARK: - Subclasses
// 4 个子类, ResponseSerialization 分别对他们做了扩展, 用来解析数据
// MARK: - DataRequest
// 使用URLSessionDataTask 处理普通请求, data 对象写在内存, 小数据, 小文件
/// `Request` subclass which handles in-memory `Data` download using `URLSessionDataTask`.
public class DataRequest: Request {
    /// `URLRequestConvertible` value used to create `URLRequest`s for this instance.
    /// 用来创建URLRequest 对象的协议对象
    public let convertible: URLRequestConvertible
    /// `Data` read from the server so far.
    /// 开放给外部的计算属性
    public var data: Data? { mutableData }

    /// Protected storage for the `Data` read by the instance.
    /// 私有的线程安全的Data 对象, 保存请求的数据
    @Protected
    private var mutableData: Data? = nil

    /// Creates a `DataRequest` using the provided parameters.
    ///
    /// - Parameters:
    ///   - id:                 `UUID` used for the `Hashable` and `Equatable` implementations. `UUID()` by default.
    ///   - convertible:        `URLRequestConvertible` value used to create `URLRequest`s for this instance.
    ///   - underlyingQueue:    `DispatchQueue` on which all internal `Request` work is performed.
    ///   - serializationQueue: `DispatchQueue` on which all serialization work is performed. By default targets
    ///                         `underlyingQueue`, but can be passed another queue from a `Session`.
    ///   - eventMonitor:       `EventMonitor` called for event callbacks from internal `Request` actions.
    ///   - interceptor:        `RequestInterceptor` used throughout the request lifecycle.
    ///   - delegate:           `RequestDelegate` that provides an interface to actions not performed by the `Request`.
    /// 初始化方法比父类多了1 个参数: 用来初始化URLRequest 对象的URLRequestConvertible
    init(id: UUID = UUID(),
         convertible: URLRequestConvertible,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: EventMonitor?,
         interceptor: RequestInterceptor?,
         delegate: RequestDelegate) {
        self.convertible = convertible

        super.init(id: id,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   delegate: delegate)
    }
    // 重置请求时要把已下载的data 清空
    override func reset() {
        super.reset()

        mutableData = nil
    }

    /// Called when `Data` is received by this instance.
    ///
    /// - Note: Also calls `updateDownloadProgress`.
    ///
    /// - Parameter data: The `Data` received.
    /// 当task 收到data 时, 由SessionDelegate 调用, 保存数据
    func didReceive(data: Data) {
        if self.data == nil {
            mutableData = data
        } else {
            // 追加
            $mutableData.write { $0?.append(data) }
        }
        // 更新下载进度
        updateDownloadProgress()
    }
    // 必须实现的父类方法, 返回DataRequest 对应的Task
    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        // 因为URLRequest 在swift 里是struct, 所以先用赋值来复制一下
        let copiedRequest = request
        return session.dataTask(with: copiedRequest)
    }

    /// Called to update the `downloadProgress` of the instance.
    /// 更新下载进度(已下载字节/待下载字节)
    func updateDownloadProgress() {
        let totalBytesReceived = Int64(data?.count ?? 0)
        let totalBytesExpected = task?.response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown

        downloadProgress.totalUnitCount = totalBytesExpected
        downloadProgress.completedUnitCount = totalBytesReceived
        // 在进度回调队列调用进度回调
        downloadProgressHandler?.queue.async { self.downloadProgressHandler?.handler(self.downloadProgress) }
    }

    /// Validates the request, using the specified closure.
    ///
    /// - Note: If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter validation: `Validation` closure used to validate the response.
    ///
    /// - Returns:              The instance.
    /// 添加validation, 方法会创建一个无出入参数的闭包, 用来执行validation 校验, 然后把这个闭包暂存起来
    /// 判断当前URLRequest, URLSessionTask, 下载的Data 是否有效
    @discardableResult
    public func validate(_ validation: @escaping Validation) -> Self {
        let validator: () -> Void = { [unowned self] in
            // 不能有错误, 必须有响应
            guard self.error == nil, let response = self.response else { return }

            let result = validation(self.request, response, self.data)

            if case let .failure(error) = result { self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error))) }

            self.eventMonitor?.request(self,
                                       didValidateRequest: self.request,
                                       response: response,
                                       data: self.data,
                                       withResult: result)
        }
        // 把闭包加入到数组
        $validators.write { $0.append(validator) }

        return self
    }
}

// MARK: - DataStreamRequest
// 处理流
/// `Request` subclass which streams HTTP response `Data` through a `Handler` closure.
/// 封装成DataStreamRequest.Stream 类型, (Data，完成，错误)
/// 收到数据时, 对全部的回调逐个调用, 完成一个, 删除一个
/// 选择创建IOStream, 请求会立即发送, 调用方会获得InputStream, DataStreamRequest使用对应的OutputStream往外写数据, 上层可以根据需要, 转换为Data保存在内存, 或者磁盘
public final class DataStreamRequest: Request {
    /// Closure type handling `DataStreamRequest.Stream` values.
    /// 定义调用方用来处理Stream 的回调, 该回调可以抛出错误, 可以控制抛出错误时是否取消请求
    public typealias Handler<Success, Failure: Error> = (Stream<Success, Failure>) throws -> Void

    /// Type encapsulating an `Event` as it flows through the stream, as well as a `CancellationToken` which can be used
    /// to stop the stream at any time.
    /// 封装了数据流对象 + 取消token, 用来给上层处理数据使用
    public struct Stream<Success, Failure: Error> {
        /// Latest `Event` from the stream.
        /// 最新的流事件(数据或者错误)
        public let event: Event<Success, Failure>
        /// Token used to cancel the stream.
        /// 用来取消数据流的token, 其实只是封装了DataStreamRequest 对象, 有一个cancel 方法
        public let token: CancellationToken

        /// Cancel the ongoing stream by canceling the underlying `DataStreamRequest`.
        /// 取消数据流(取消请求)
        public func cancel() {
            token.cancel()
        }
    }

    /// Type representing an event flowing through the stream. Contains either the `Result` of processing streamed
    /// `Data` or the completion of the stream.
    /// 封装了数据流, 包括: 数据, 错误, 完成三种
    public enum Event<Success, Failure: Error> {
        /// Output produced every time the instance receives additional `Data`. The associated value contains the
        /// `Result` of processing the incoming `Data`.
        /// 数据或者错误
        case stream(Result<Success, Failure>)
        /// Output produced when the instance has completed, whether due to stream end, cancellation, or an error.
        /// Associated `Completion` value contains the final state.
        /// 完成信息(完成状态) (可能是请求完成, 请求取消, 请求出错)
        case complete(Completion)
    }

    /// Value containing the state of a `DataStreamRequest` when the stream was completed.
    /// 当数据流完成时, 携带在Event 里的数据
    public struct Completion {
        /// Last `URLRequest` issued by the instance.
        /// 最后发出的请求
        public let request: URLRequest?
        /// Last `HTTPURLResponse` received by the instance.
        /// 最后收到的响应
        public let response: HTTPURLResponse?
        /// Last `URLSessionTaskMetrics` produced for the instance.
        /// 最后收到的请求指标
        public let metrics: URLSessionTaskMetrics?
        /// `AFError` produced for the instance, if any.
        /// 数据流出错的错误
        public let error: AFError?
    }

    /// Type used to cancel an ongoing stream.
    /// 用来取消数据流时, 取消请求的token
    public struct CancellationToken {
        weak var request: DataStreamRequest?

        init(_ request: DataStreamRequest) {
            self.request = request
        }

        /// Cancel the ongoing stream by canceling the underlying `DataStreamRequest`.
        /// 取消数据流时直接取消请求
        public func cancel() {
            request?.cancel()
        }
    }

    /// `URLRequestConvertible` value used to create `URLRequest`s for this instance.
    /// 用来创建
    public let convertible: URLRequestConvertible
    /// Whether or not the instance will be cancelled if stream parsing encounters an error.
    /// 如果数据流解析出错是否直接取消请求, 默认为false
    public let automaticallyCancelOnStreamError: Bool

    /// Internal mutable state specific to this type.
    /// 包装需要线程安全操作的几个数据
    struct StreamMutableState {
        /// `OutputStream` bound to the `InputStream` produced by `asInputStream`, if it has been called.
        /// 当把DataStreamRequest 作为InputStream 时, 会创建该对象并把输出流转绑定给InputStream
        var outputStream: OutputStream?
        /// Stream closures called as `Data` is received.
        /// 内部用来处理Data 的数据流回调数组, 主要工作为: 封装Stream 对象交给上层回调处理, 然后记录正在处理的数据流个数, 全部处理完之后需要执行完成回调
        var streams: [(_ data: Data) -> Void] = []
        /// Number of currently executing streams. Used to ensure completions are only fired after all streams are
        /// enqueued.
        /// 当前正在执行的流的个数
        var numberOfExecutingStreams = 0
        /// Completion calls enqueued while streams are still executing.
        /// 当数据流还没完成时暂存完成回调的数组
        var enqueuedCompletionEvents: [() -> Void] = []
    }

    @Protected
    var streamMutableState = StreamMutableState()

    /// Creates a `DataStreamRequest` using the provided parameters.
    ///
    /// - Parameters:
    ///   - id:                               `UUID` used for the `Hashable` and `Equatable` implementations. `UUID()`
    ///                                        by default.
    ///   - convertible:                      `URLRequestConvertible` value used to create `URLRequest`s for this
    ///                                        instance.
    ///   - automaticallyCancelOnStreamError: `Bool` indicating whether the instance will be cancelled when an `Error`
    ///                                       is thrown while serializing stream `Data`.
    ///   - underlyingQueue:                  `DispatchQueue` on which all internal `Request` work is performed.
    ///   - serializationQueue:               `DispatchQueue` on which all serialization work is performed. By default
    ///                                       targets
    ///                                       `underlyingQueue`, but can be passed another queue from a `Session`.
    ///   - eventMonitor:                     `EventMonitor` called for event callbacks from internal `Request` actions.
    ///   - interceptor:                      `RequestInterceptor` used throughout the request lifecycle.
    ///   - delegate:                         `RequestDelegate` that provides an interface to actions not performed by
    ///                                       the `Request`.
    /// 比父类多了两个参数: 1. URLRequestConvertible, 2. 是否在Stream 处理失败时取消请求
    init(id: UUID = UUID(),
         convertible: URLRequestConvertible,
         automaticallyCancelOnStreamError: Bool,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: EventMonitor?,
         interceptor: RequestInterceptor?,
         delegate: RequestDelegate) {
        self.convertible = convertible
        self.automaticallyCancelOnStreamError = automaticallyCancelOnStreamError

        super.init(id: id,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   delegate: delegate)
    }
    // task 也是URLSessionDataTask
    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        let copiedRequest = request
        return session.dataTask(with: copiedRequest)
    }
    // 完成时要把OutputStream 关闭
    override func finish(error: AFError? = nil) {
        $streamMutableState.write { state in
            state.outputStream?.close()
        }

        super.finish(error: error)
    }
    // 收到Data 处理
    func didReceive(data: Data) {
        $streamMutableState.write { state in
            #if !(os(Linux) || os(Windows))
            if let stream = state.outputStream {
                // 如果有作为InputStream, 就会创建对应的OutputStream, 输出数据
                underlyingQueue.async {
                    var bytes = Array(data)
                    stream.write(&bytes, maxLength: bytes.count)
                }
            }
            #endif
            // 当前正在处理的回调个数 + 新的要处理的回调个数
            state.numberOfExecutingStreams += state.streams.count
            let localState = state
            // 处理数据
            underlyingQueue.async { localState.streams.forEach { $0(data) } }
        }
    }

    /// Validates the `URLRequest` and `HTTPURLResponse` received for the instance using the provided `Validation` closure.
    ///
    /// - Parameter validation: `Validation` closure used to validate the request and response.
    ///
    /// - Returns:              The `DataStreamRequest`.
    /// 添加有效性判断回调
    @discardableResult
    public func validate(_ validation: @escaping Validation) -> Self {
        let validator: () -> Void = { [unowned self] in
            guard self.error == nil, let response = self.response else { return }

            let result = validation(self.request, response)

            if case let .failure(error) = result {
                self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error)))
            }

            self.eventMonitor?.request(self,
                                       didValidateRequest: self.request,
                                       response: response,
                                       withResult: result)
        }

        $validators.write { $0.append(validator) }

        return self
    }

    #if !(os(Linux) || os(Windows))
    /// Produces an `InputStream` that receives the `Data` received by the instance.
    ///
    /// - Note: The `InputStream` produced by this method must have `open()` called before being able to read `Data`.
    ///         Additionally, this method will automatically call `resume()` on the instance, regardless of whether or
    ///         not the creating session has `startRequestsImmediately` set to `true`.
    ///
    /// - Parameter bufferSize: Size, in bytes, of the buffer between the `OutputStream` and `InputStream`.
    ///
    /// - Returns:              The `InputStream` bound to the internal `OutboundStream`.
    /// 变换成InputStream 供外部操作, 调用该方法后会直接发送请求, 返回给上层的InputStream 在读取数据之前必须先open(), 结束时候必须close()
    public func asInputStream(bufferSize: Int = 1024) -> InputStream? {
        // 创建完IOStream 之后就会立刻发送请求, 无视是否立即发送请求的控制参数
        defer { resume() }

        var inputStream: InputStream?
        $streamMutableState.write { state in
            // 创建一对IOStream, OutputStream 往InputStream 写, buffer 默认1k
            Foundation.Stream.getBoundStreams(withBufferSize: bufferSize,
                                              inputStream: &inputStream,
                                              outputStream: &state.outputStream)
            // 打开OutputStream, 准备读取数据
            state.outputStream?.open()
        }

        return inputStream
    }
    #endif
    // 执行一个可以抛出错误的回调, 捕捉异常, 取消请求并抛出错误, (在ResponseSerialization 中调用)
    func capturingError(from closure: () throws -> Void) {
        do {
            try closure()
        } catch {
            self.error = error.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: error)))
            cancel()
        }
    }
    // 添加数据流完成回调与队列
    func appendStreamCompletion<Success, Failure>(on queue: DispatchQueue,
                                                  stream: @escaping Handler<Success, Failure>) {
        appendResponseSerializer { // 先添加一个解析回调
            self.underlyingQueue.async { // 回调内容为在内部队列执行添加一个解析完成的回调
                self.responseSerializerDidComplete {
                    self.$streamMutableState.write { state in // 解析完成的回调内容为操作$streamMutableState
                        guard state.numberOfExecutingStreams == 0 else {
                            state.enqueuedCompletionEvents.append { // 如果还有流在处理数据, 就把完成回调追加到数组里
                                self.enqueueCompletion(on: queue, stream: stream)
                            }

                            return
                        }
                        // 否则直接执行回调
                        self.enqueueCompletion(on: queue, stream: stream)
                    }
                }
            }
        }
        // 这样操作可以保证完成回调在其他所有的解析器处理完成后添加
    }
    // 发送完成事件
    func enqueueCompletion<Success, Failure>(on queue: DispatchQueue,
                                             stream: @escaping Handler<Success, Failure>) {
        queue.async {
            do {
                // 创建完成事件
                let completion = Completion(request: self.request,
                                            response: self.response,
                                            metrics: self.metrics,
                                            error: self.error)
                try stream(.init(event: .complete(completion), token: .init(self)))
            } catch {
                // Ignore error, as errors on Completion can't be handled anyway.
                // 忽略错误, 完成错误无法被处理, 数据已经完整了
            }
        }
    }
}
// 快速取得内部数据
extension DataStreamRequest.Stream {
    /// Incoming `Result` values from `Event.stream`.
    public var result: Result<Success, Failure>? {
        guard case let .stream(result) = event else { return nil }

        return result
    }

    /// `Success` value of the instance, if any.
    public var value: Success? {
        guard case let .success(value) = result else { return nil }

        return value
    }

    /// `Failure` value of the instance, if any.
    public var error: Failure? {
        guard case let .failure(error) = result else { return nil }

        return error
    }

    /// `Completion` value of the instance, if any.
    public var completion: DataStreamRequest.Completion? {
        guard case let .complete(completion) = event else { return nil }

        return completion
    }
}

// MARK: - DownloadRequest
// 处理下载请求
// 文件以文件形式保存在磁盘上
/// `Request` subclass which downloads `Data` to a file on disk using `URLSessionDownloadTask`.
/// 先定义了一个符合OptionSet 协议的结构体来决定本地文件的保存策略
public class DownloadRequest: Request {
    /// A set of options to be executed prior to moving a downloaded file from the temporary `URL` to the destination
    /// `URL`.
    public struct Options: OptionSet {
        /// Specifies that intermediate directories for the destination URL should be created.
        /// 是否创建中间目录
        public static let createIntermediateDirectories = Options(rawValue: 1 << 0)
        /// Specifies that any previous file at the destination `URL` should be removed.
        /// 下载文件前是否先移除旧文件
        public static let removePreviousFile = Options(rawValue: 1 << 1)

        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    // MARK: Destination
    // 下载目标路径
    /// A closure executed once a `DownloadRequest` has successfully completed in order to determine where to move the
    /// temporary file written to during the download process. The closure takes two arguments: the temporary file URL
    /// and the `HTTPURLResponse`, and returns two values: the file URL where the temporary file should be moved and
    /// the options defining how the file should be moved.
    ///
    /// - Note: Downloads from a local `file://` `URL`s do not use the `Destination` closure, as those downloads do not
    ///         return an `HTTPURLResponse`. Instead the file is merely moved within the temporary directory.
    /// 下载任务会先把文件下载到临时的缓存路径, 然后将文件拷贝到下载目标路径, 使用闭包来决定可以把下载路径的决定推迟到下载完成时, 可以根据临时文件目录与下载响应头来决定下载目标路径以及文件保存策略
    /// 如果是下载本地文件(url为file:// 开头的), 回调不会有response
    public typealias Destination = (_ temporaryURL: URL,
                                    _ response: HTTPURLResponse) -> (destinationURL: URL, options: Options)

    /// Creates a download file destination closure which uses the default file manager to move the temporary file to a
    /// file URL in the first available directory with the specified search path directory and search path domain mask.
    ///
    /// - Parameters:
    ///   - directory: The search path directory. `.documentDirectory` by default.
    ///   - domain:    The search path domain mask. `.userDomainMask` by default.
    ///   - options:   `DownloadRequest.Options` used when moving the downloaded file to its destination. None by
    ///                default.
    /// - Returns: The `Destination` closure.
    /// 创建默认建议的下载路径回调(document根目录)
    public class func suggestedDownloadDestination(for directory: FileManager.SearchPathDirectory = .documentDirectory,
                                                   in domain: FileManager.SearchPathDomainMask = .userDomainMask,
                                                   options: Options = []) -> Destination {
        { temporaryURL, response in
            let directoryURLs = FileManager.default.urls(for: directory, in: domain)
            let url = directoryURLs.first?.appendingPathComponent(response.suggestedFilename!) ?? temporaryURL

            return (url, options)
        }
    }

    /// Default `Destination` used by Alamofire to ensure all downloads persist. This `Destination` prepends
    /// `Alamofire_` to the automatically generated download name and moves it within the temporary directory. Files
    /// with this destination must be additionally moved if they should survive the system reclamation of temporary
    /// space.
    /// 默认的下载路径回调(处理见下面方法)
    static let defaultDestination: Destination = { url, _ in
        (defaultDestinationURL(url), [])
    }

    /// Default `URL` creation closure. Creates a `URL` in the temporary directory with `Alamofire_` prepended to the
    /// provided file name.
    /// 返回默认的文件储存路径(只是把默认的文件名重命名为加上Alamofire_ 前缀, 文件还是在缓存目录, 会被系统删除, 如果要保存文件, 需要转移到其他目录)
    static let defaultDestinationURL: (URL) -> URL = { url in
        let filename = "Alamofire_\(url.lastPathComponent)"
        let destination = url.deletingLastPathComponent().appendingPathComponent(filename)

        return destination
    }

    // MARK: Downloadable

    /// Type describing the source used to create the underlying `URLSessionDownloadTask`.
    /// 下载请求的下载源
    public enum Downloadable {
        /// Download should be started from the `URLRequest` produced by the associated `URLRequestConvertible` value.
        /// 从URLRequest 下载
        case request(URLRequestConvertible)
        /// Download should be started from the associated resume `Data` value.
        /// 断点续传
        case resumeData(Data)
    }

    // MARK: Mutable State

    /// Type containing all mutable state for `DownloadRequest` instances.
    private struct DownloadRequestMutableState {
        /// Possible resume `Data` produced when cancelling the instance.
        /// 断点续传的任务被取消时, 需要被处理的已下载数据
        var resumeData: Data?
        /// `URL` to which `Data` is being downloaded.
        /// 下载完成后的文件保存路径
        var fileURL: URL?
    }

    /// Protected mutable state specific to `DownloadRequest`.
    /// 包装器
    @Protected
    private var mutableDownloadState = DownloadRequestMutableState()

    /// If the download is resumable and is eventually cancelled or fails, this value may be used to resume the download
    /// using the `download(resumingWith data:)` API.
    ///
    /// - Note: For more information about `resumeData`, see [Apple's documentation](https://developer.apple.com/documentation/foundation/urlsessiondownloadtask/1411634-cancel).
    /// 开放给外部获取
    public var resumeData: Data? {
        #if !(os(Linux) || os(Windows))
        return $mutableDownloadState.resumeData ?? error?.downloadResumeData
        #else
        return $mutableDownloadState.resumeData
        #endif
    }

    /// If the download is successful, the `URL` where the file was downloaded.
    public var fileURL: URL? { $mutableDownloadState.fileURL }

    // MARK: Initial State
    // 初始化与两个初始化时需要确定的参数
    /// `Downloadable` value used for this instance.
    /// 下载源
    public let downloadable: Downloadable
    /// The `Destination` to which the downloaded file is moved.
    /// 下载路径回调
    let destination: Destination

    /// Creates a `DownloadRequest` using the provided parameters.
    ///
    /// - Parameters:
    ///   - id:                 `UUID` used for the `Hashable` and `Equatable` implementations. `UUID()` by default.
    ///   - downloadable:       `Downloadable` value used to create `URLSessionDownloadTasks` for the instance.
    ///   - underlyingQueue:    `DispatchQueue` on which all internal `Request` work is performed.
    ///   - serializationQueue: `DispatchQueue` on which all serialization work is performed. By default targets
    ///                         `underlyingQueue`, but can be passed another queue from a `Session`.
    ///   - eventMonitor:       `EventMonitor` called for event callbacks from internal `Request` actions.
    ///   - interceptor:        `RequestInterceptor` used throughout the request lifecycle.
    ///   - delegate:           `RequestDelegate` that provides an interface to actions not performed by the `Request`
    ///   - destination:        `Destination` closure used to move the downloaded file to its final location.
    init(id: UUID = UUID(),
         downloadable: Downloadable,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: EventMonitor?,
         interceptor: RequestInterceptor?,
         delegate: RequestDelegate,
         destination: @escaping Destination) {
        self.downloadable = downloadable
        self.destination = destination

        super.init(id: id,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   delegate: delegate)
    }
    // 重试时清除数据
    override func reset() {
        super.reset()

        $mutableDownloadState.write {
            $0.resumeData = nil
            $0.fileURL = nil
        }
    }

    /// Called when a download has finished.
    /// 下载与取消的处理
    /// - Parameters:
    ///   - task:   `URLSessionTask` that finished the download.
    ///   - result: `Result` of the automatic move to `destination`.
    ///   URLSession 下载完成/失败时, 回调过来更新状态
    func didFinishDownloading(using task: URLSessionTask, with result: Result<URL, AFError>) {
        eventMonitor?.request(self, didFinishDownloadingUsing: task, with: result)

        switch result {
        case let .success(url): $mutableDownloadState.fileURL = url
        case let .failure(error): self.error = error
        }
    }

    /// Updates the `downloadProgress` using the provided values.
    ///
    /// - Parameters:
    ///   - bytesWritten:              Total bytes written so far.
    ///   - totalBytesExpectedToWrite: Total bytes expected to write.
    ///   URLSession 下载时, 回调更新进度
    func updateDownloadProgress(bytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        downloadProgress.totalUnitCount = totalBytesExpectedToWrite
        downloadProgress.completedUnitCount += bytesWritten

        downloadProgressHandler?.queue.async { self.downloadProgressHandler?.handler(self.downloadProgress) }
    }
    // 新文件下载
    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        session.downloadTask(with: request)
    }

    /// Creates a `URLSessionTask` from the provided resume data.
    ///
    /// - Parameters:
    ///   - data:    `Data` used to resume the download.
    ///   - session: `URLSession` used to create the `URLSessionTask`.
    ///
    /// - Returns:   The `URLSessionTask` created.
    /// 断点续传
    public func task(forResumeData data: Data, using session: URLSession) -> URLSessionTask {
        session.downloadTask(withResumeData: data)
    }

    /// Cancels the instance. Once cancelled, a `DownloadRequest` can no longer be resumed or suspended.
    ///
    /// - Note: This method will NOT produce resume data. If you wish to cancel and produce resume data, use
    ///         `cancel(producingResumeData:)` or `cancel(byProducingResumeData:)`.
    ///
    /// - Returns: The instance.
    /// 1. 直接取消请求, 不设置resumeData 属性给监听器, 没有回调处理已下载数据
    @discardableResult
    override public func cancel() -> Self {
        cancel(producingResumeData: false)
    }

    /// Cancels the instance, optionally producing resume data. Once cancelled, a `DownloadRequest` can no longer be
    /// resumed or suspended.
    ///
    /// - Note: If `producingResumeData` is `true`, the `resumeData` property will be populated with any resume data, if
    ///         available.
    ///
    /// - Returns: The instance.
    /// 2. 取消下载, 并判断是否需要填充resumeData 属性给监听器, 没有回调处理已下载数据
    @discardableResult
    public func cancel(producingResumeData shouldProduceResumeData: Bool) -> Self {
        cancel(optionallyProducingResumeData: shouldProduceResumeData ? { _ in } : nil)
    }

    /// Cancels the instance while producing resume data. Once cancelled, a `DownloadRequest` can no longer be resumed
    /// or suspended.
    ///
    /// - Note: The resume data passed to the completion handler will also be available on the instance's `resumeData`
    ///         property.
    ///
    /// - Parameter completionHandler: The completion handler that is called when the download has been successfully
    ///                                cancelled. It is not guaranteed to be called on a particular queue, so you may
    ///                                want use an appropriate queue to perform your work.
    ///
    /// - Returns:                     The instance.
    /// 3. 取消下载, 用一个回调来处理已下载数据, 会先填充resumeData 属性, 通知监听器后调用回调
    @discardableResult
    public func cancel(byProducingResumeData completionHandler: @escaping (_ data: Data?) -> Void) -> Self {
        cancel(optionallyProducingResumeData: completionHandler)
    }

    /// Internal implementation of cancellation that optionally takes a resume data handler. If no handler is passed,
    /// cancellation is performed without producing resume data.
    ///
    /// - Parameter completionHandler: Optional resume data handler.
    ///
    /// - Returns:                     The instance.
    /// 上面1, 2, 3 的整合
    private func cancel(optionallyProducingResumeData completionHandler: ((_ resumeData: Data?) -> Void)?) -> Self {
        // 保证线程安全
        $mutableState.write { mutableState in
            // 先判断能否取消
            guard mutableState.state.canTransitionTo(.cancelled) else { return }
            // 更新状态
            mutableState.state = .cancelled
            // 先告知自己取消被调用了, 父类会告知监听器
            underlyingQueue.async { self.didCancel() }

            guard let task = mutableState.tasks.last as? URLSessionDownloadTask, task.state != .completed else {
                // 如果下载完成的话, 走finish 逻辑
                underlyingQueue.async { self.finish() }
                return
            }

            if let completionHandler = completionHandler {
                // Resume to ensure metrics are gathered.
                // 取消时处理已下载数据的回调
                // 先恢复一下确保请求指标被获取到了
                task.resume()
                task.cancel { resumeData in
                    // 填入resumeData 属性
                    self.$mutableDownloadState.resumeData = resumeData
                    // 告知自己取消成功, 父类会告知监听器
                    self.underlyingQueue.async { self.didCancelTask(task) }
                    // 执行已下载数据处理回调
                    completionHandler(resumeData)
                }
            } else {
                // Resume to ensure metrics are gathered.
                // 没有处理下载数据的回调
                task.resume()
                // 直接取消
                task.cancel()
                // 通知
                self.underlyingQueue.async { self.didCancelTask(task) }
            }
        }

        return self
    }

    /// Validates the request, using the specified closure.
    ///
    /// - Note: If validation fails, subsequent calls to response handlers will have an associated error.
    ///
    /// - Parameter validation: `Validation` closure to validate the response.
    ///
    /// - Returns:              The instance.
    /// 响应的有效性判断
    @discardableResult
    public func validate(_ validation: @escaping Validation) -> Self {
        let validator: () -> Void = { [unowned self] in
            guard self.error == nil, let response = self.response else { return }

            let result = validation(self.request, response, self.fileURL)

            if case let .failure(error) = result {
                self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error)))
            }

            self.eventMonitor?.request(self,
                                       didValidateRequest: self.request,
                                       response: response,
                                       fileURL: self.fileURL,
                                       withResult: result)
        }

        $validators.write { $0.append(validator) }

        return self
    }
}

// MARK: - UploadRequest
// 处理上传
// 上传请求是DataRequest 的子类
/// `DataRequest` subclass which handles `Data` upload from memory, file, or stream using `URLSessionUploadTask`.
public class UploadRequest: DataRequest {
    /// Type describing the origin of the upload, whether `Data`, file, or stream.
    /// 上传源
    public enum Uploadable {
        /// Upload from the provided `Data` value.
        /// 从内存
        case data(Data)
        /// Upload from the provided file `URL`, as well as a `Bool` determining whether the source file should be
        /// automatically removed once uploaded.
        /// 从文件上传, 并可以设置上传完成后是否删除源文件
        case file(URL, shouldRemove: Bool)
        /// Upload from the provided `InputStream`.
        /// 从流上传
        case stream(InputStream)
    }

    // MARK: Initial State

    /// The `UploadableConvertible` value used to produce the `Uploadable` value for this instance.
    /// 用来创建上传源的协议
    public let upload: UploadableConvertible

    /// `FileManager` used to perform cleanup tasks, including the removal of multipart form encoded payloads written
    /// to disk.
    /// 文件管理器, 用来清除任务, 包括写在硬盘上的多表单上传数据
    public let fileManager: FileManager

    // MARK: Mutable State

    /// `Uploadable` value used by the instance.
    /// 上传源, 开始请求时才创建. 可选是因为, 从上传源协议对象创建的时候, 是可以失败的
    public var uploadable: Uploadable?

    /// Creates an `UploadRequest` using the provided parameters.
    ///
    /// - Parameters:
    ///   - id:                 `UUID` used for the `Hashable` and `Equatable` implementations. `UUID()` by default.
    ///   - convertible:        `UploadConvertible` value used to determine the type of upload to be performed.
    ///   - underlyingQueue:    `DispatchQueue` on which all internal `Request` work is performed.
    ///   - serializationQueue: `DispatchQueue` on which all serialization work is performed. By default targets
    ///                         `underlyingQueue`, but can be passed another queue from a `Session`.
    ///   - eventMonitor:       `EventMonitor` called for event callbacks from internal `Request` actions.
    ///   - interceptor:        `RequestInterceptor` used throughout the request lifecycle.
    ///   - fileManager:        `FileManager` used to perform cleanup tasks, including the removal of multipart form
    ///                         encoded payloads written to disk.
    ///   - delegate:           `RequestDelegate` that provides an interface to actions not performed by the `Request`.
    init(id: UUID = UUID(),
         convertible: UploadConvertible,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: EventMonitor?,
         interceptor: RequestInterceptor?,
         fileManager: FileManager,
         delegate: RequestDelegate) {
        upload = convertible
        self.fileManager = fileManager

        super.init(id: id,
                   convertible: convertible,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   delegate: delegate)
    }

    /// Called when the `Uploadable` value has been created from the `UploadConvertible`.
    ///
    /// - Parameter uploadable: The `Uploadable` that was created.
    /// 告知监听器 创建上传源成功(Session 中调用)
    func didCreateUploadable(_ uploadable: Uploadable) {
        self.uploadable = uploadable

        eventMonitor?.request(self, didCreateUploadable: uploadable)
    }

    /// Called when the `Uploadable` value could not be created.
    ///
    /// - Parameter error: `AFError` produced by the failure.
    /// 告知监听器 创建上传源失败(Session 中调用), 然后走重试或者完成逻辑
    func didFailToCreateUploadable(with error: AFError) {
        self.error = error

        eventMonitor?.request(self, didFailToCreateUploadableWithError: error)

        retryOrFinish(error: error)
    }
    // 用URLRequest 跟URLSession 创建URLSessionUploadTask(Session 中调用)
    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        guard let uploadable = uploadable else {
            fatalError("Attempting to create a URLSessionUploadTask when Uploadable value doesn't exist.")
        }

        switch uploadable {
        case let .data(data): return session.uploadTask(with: request, from: data)
        case let .file(url, _): return session.uploadTask(with: request, fromFile: url)
        case .stream: return session.uploadTask(withStreamedRequest: request)
        }
    }
    // 重试时清空数据, 重试时, 上传源必须重新创建
    override func reset() {
        // Uploadable must be recreated on every retry.
        uploadable = nil

        super.reset()
    }

    /// Produces the `InputStream` from `uploadable`, if it can.
    ///
    /// - Note: Calling this method with a non-`.stream` `Uploadable` is a logic error and will crash.
    ///
    /// - Returns: The `InputStream`.
    /// 转换为InputStream 供外部连接, 必须使用Uploadable.stream, 否则会抛出异常
    func inputStream() -> InputStream {
        guard let uploadable = uploadable else {
            fatalError("Attempting to access the input stream but the uploadable doesn't exist.")
        }

        guard case let .stream(stream) = uploadable else {
            fatalError("Attempted to access the stream of an UploadRequest that wasn't created with one.")
        }

        eventMonitor?.request(self, didProvideInputStream: stream)

        return stream
    }
    // 请求完成时, 清理任务(删除源文件)
    override public func cleanup() {
        defer { super.cleanup() }

        guard
            let uploadable = uploadable,
            case let .file(url, shouldRemove) = uploadable,
            shouldRemove
        else { return }

        try? fileManager.removeItem(at: url)
    }
}

/// A type that can produce an `UploadRequest.Uploadable` value.
/// 定义UploadableConvertible 协议用来创建上传源的协议
public protocol UploadableConvertible {
    /// Produces an `UploadRequest.Uploadable` value from the instance.
    ///
    /// - Returns: The `UploadRequest.Uploadable`.
    /// - Throws:  Any `Error` produced during creation.
    func createUploadable() throws -> UploadRequest.Uploadable
}
/// 扩展了UploadRequest.Uploadable 实现UploadableConvertible 协议， 直接返回自己 外部就不用自己写生成上传源的类， 可以直接用
extension UploadRequest.Uploadable: UploadableConvertible {
    public func createUploadable() throws -> UploadRequest.Uploadable {
        self
    }
}

/// A type that can be converted to an upload, whether from an `UploadRequest.Uploadable` or `URLRequestConvertible`.
public protocol UploadConvertible: UploadableConvertible & URLRequestConvertible {}
