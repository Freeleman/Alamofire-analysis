//
//  EventMonitor.swift
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

/// Protocol outlining the lifetime events inside Alamofire. It includes both events received from the various
/// `URLSession` delegate protocols as well as various events from the lifetime of `Request` and its subclasses.
/// 监听请求过程中的各个状态, 定义一个回调监听器的队列, 默认主队列
/// 相关接口实现的类:
/// AlamofireNotifications 类, 不同阶段发送通知使用
/// CompositeEventMonitor, 组合不同监听器对象
/// ClosureEventMonitor, 持有多个闭包, 把代理调用转换成闭包调用
///
/// SessionDelegate 持有一个CompositeEventMonitor 组合监听器对象, Session 初始化时, 接受一个监听器数组初始化参数, 加上AlamofireNotifications监听器组合成一个CompositeEventMonitor 交给SessionDelegate 持有, 再session 的代理方法中, 回调这些监听器
/// 每个Request 对象也持有一个CompositeEventMonitor, 在Session 中初始化Request 对象时, 把SessionDelegate 持有的组合模拟器传递给了创建的Request, 在Request 响应状态时, 回调这些监听器
///
/// URLSession 代理, taskDelegate 代理, 和Request 和子类请求周期的代理
public protocol EventMonitor {
    /// The `DispatchQueue` onto which Alamofire's root `CompositeEventMonitor` will dispatch events. `.main` by default.
    /// 监听器回调队列, 默认主
    var queue: DispatchQueue { get }

    // MARK: - URLSession Events

    // MARK: URLSessionDelegate Events

    /// Event called during `URLSessionDelegate`'s `urlSession(_:didBecomeInvalidWithError:)` method.
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?)

    // MARK: URLSessionTaskDelegate Events

    /// Event called during `URLSessionTaskDelegate`'s `urlSession(_:task:didReceive:completionHandler:)` method.
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)

    /// Event called during `URLSessionTaskDelegate`'s `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` method.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64)

    /// Event called during `URLSessionTaskDelegate`'s `urlSession(_:task:needNewBodyStream:)` method.
    func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask)

    /// Event called during `URLSessionTaskDelegate`'s `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` method.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest)

    /// Event called during `URLSessionTaskDelegate`'s `urlSession(_:task:didFinishCollecting:)` method.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)

    /// Event called during `URLSessionTaskDelegate`'s `urlSession(_:task:didCompleteWithError:)` method.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)

    /// Event called during `URLSessionTaskDelegate`'s `urlSession(_:taskIsWaitingForConnectivity:)` method.
    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask)

    // MARK: URLSessionDataDelegate Events

    /// Event called during `URLSessionDataDelegate`'s `urlSession(_:dataTask:didReceive:)` method.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)

    /// Event called during `URLSessionDataDelegate`'s `urlSession(_:dataTask:willCacheResponse:completionHandler:)` method.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse)

    // MARK: URLSessionDownloadDelegate Events

    /// Event called during `URLSessionDownloadDelegate`'s `urlSession(_:downloadTask:didResumeAtOffset:expectedTotalBytes:)` method.
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didResumeAtOffset fileOffset: Int64,
                    expectedTotalBytes: Int64)

    /// Event called during `URLSessionDownloadDelegate`'s `urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)` method.
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64)

    /// Event called during `URLSessionDownloadDelegate`'s `urlSession(_:downloadTask:didFinishDownloadingTo:)` method.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)

    // MARK: - Request Events
    // Request Events 和子类相关请求周期事件
    /// Event called when a `URLRequest` is first created for a `Request`. If a `RequestAdapter` is active, the
    /// `URLRequest` will be adapted before being issued.
    /// 原始URLRequest 成功回调, 如果request 有适配器, 解析爱来回使用适配器处理原始URLRequest, 没有适配器直接回调创建Request 方法
    func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest)

    /// Event called when the attempt to create a `URLRequest` from a `Request`'s original `URLRequestConvertible` value fails.
    /// 创建原始Request 失败
    func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError)

    /// Event called when a `RequestAdapter` adapts the `Request`'s initial `URLRequest`.
    /// 创建Request 成功, 在适配器处理后
    func request(_ request: Request, didAdaptInitialRequest initialRequest: URLRequest, to adaptedRequest: URLRequest)

    /// Event called when a `RequestAdapter` fails to adapt the `Request`'s initial `URLRequest`.
    func request(_ request: Request, didFailToAdaptURLRequest initialRequest: URLRequest, withError error: AFError)

    /// Event called when a final `URLRequest` is created for a `Request`.
    /// 创建Request 成功, 在适配器处理后
    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest)

    /// Event called when a `URLSessionTask` subclass instance is created for a `Request`.
    /// 创建Task 成功
    func request(_ request: Request, didCreateTask task: URLSessionTask)

    /// Event called when a `Request` receives a `URLSessionTaskMetrics` value.
    /// 请求指标成功
    func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics)

    /// Event called when a `Request` fails due to an error created by Alamofire. e.g. When certificate pinning fails.
    /// Alamofire 创建抛出错误, 比如自定义认证处理失败
    func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError)

    /// Event called when a `Request`'s task completes, possibly with an error. A `Request` may receive this event
    /// multiple times if it is retried.
    /// URLSessionTask 请求完成, 可能成功或失败, 然后判断是否要重试, 如果重试, 该回调呗调用多次
    func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?)

    /// Event called when a `Request` is about to be retried.
    /// 准备开始重试
    func requestIsRetrying(_ request: Request)

    /// Event called when a `Request` finishes and response serializers are being called.
    /// 请求完成, 开始解析响应
    func requestDidFinish(_ request: Request)
    
    /// 下面6 个方法都为主动调用Request, 影响到关联的Task 时的回调, 成对出现
    /// Event called when a `Request` receives a `resume` call.
    /// Request 调用resume 方法时候回调该方法
    func requestDidResume(_ request: Request)

    /// Event called when a `Request`'s associated `URLSessionTask` is resumed.
    /// Request 关联的URLSessionTask 继续的时候调用
    func request(_ request: Request, didResumeTask task: URLSessionTask)

    /// Event called when a `Request` receives a `suspend` call.
    /// Request suspend 挂起
    func requestDidSuspend(_ request: Request)

    /// Event called when a `Request`'s associated `URLSessionTask` is suspended.
    /// Request 关联的Task 被挂起
    func request(_ request: Request, didSuspendTask task: URLSessionTask)

    /// Event called when a `Request` receives a `cancel` call.
    /// Request 调用cancel
    func requestDidCancel(_ request: Request)

    /// Event called when a `Request`'s associated `URLSessionTask` is cancelled.
    /// Request 关联Task 被取消
    func request(_ request: Request, didCancelTask task: URLSessionTask)

    // MARK: DataRequest Events
    // DataRequest 特有事件
    /// Event called when a `DataRequest` calls a `Validation`.
    /// 检测响应是否有效成功后回调
    func request(_ request: DataRequest,
                 didValidateRequest urlRequest: URLRequest?,
                 response: HTTPURLResponse,
                 data: Data?,
                 withResult result: Request.ValidationResult)

    /// Event called when a `DataRequest` creates a `DataResponse<Data?>` value without calling a `ResponseSerializer`.
    /// DataRequest 成功创建Data 类型的DataRequest 时回调, 没有序列化
    func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>)

    /// Event called when a `DataRequest` calls a `ResponseSerializer` and creates a generic `DataResponse<Value, AFError>`.
    /// DataRequest 成功创建序列化的DataResponse 时回调
    func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>)

    // MARK: DataStreamRequest Events
    // DataStreamRequest 特有事件
    /// Event called when a `DataStreamRequest` calls a `Validation` closure.
    ///
    /// - Parameters:
    ///   - request:    `DataStreamRequest` which is calling the `Validation`.
    ///   - urlRequest: `URLRequest` of the request being validated.
    ///   - response:   `HTTPURLResponse` of the request being validated.
    ///   - result:      Produced `ValidationResult`.
    ///   检测响应有效成功
    func request(_ request: DataStreamRequest,
                 didValidateRequest urlRequest: URLRequest?,
                 response: HTTPURLResponse,
                 withResult result: Request.ValidationResult)

    /// Event called when a `DataStreamSerializer` produces a value from streamed `Data`.
    ///
    /// - Parameters:
    ///   - request: `DataStreamRequest` for which the value was serialized.
    ///   - result:  `Result` of the serialization attempt.
    ///   从Stream 中成功序列化数据后调用
    func request<Value>(_ request: DataStreamRequest, didParseStream result: Result<Value, AFError>)

    // MARK: UploadRequest Events
    // UploadRequest 特有事件
    /// Event called when an `UploadRequest` creates its `Uploadable` value, indicating the type of upload it represents.
    /// 上传请求成功创建 Uploadable 协议对象成功
    func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable)

    /// Event called when an `UploadRequest` failed to create its `Uploadable` value due to an error.
    /// 创建Uploadable 失败
    func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError)

    /// Event called when an `UploadRequest` provides the `InputStream` from its `Uploadable` value. This only occurs if
    /// the `InputStream` does not wrap a `Data` value or file `URL`.
    /// 当上传请求从InputStream 开始提供数据时回调, 只有在上传请求的InputStream 不是Data 也不是文件url 类型才会回调
    func request(_ request: UploadRequest, didProvideInputStream stream: InputStream)

    // MARK: DownloadRequest Events
    // DownloadRequest 特有事件
    /// Event called when a `DownloadRequest`'s `URLSessionDownloadTask` finishes and the temporary file has been moved.
    /// 下载Task 完成, 且缓存文件被清除之后回调
    func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>)

    /// Event called when a `DownloadRequest`'s `Destination` closure is called and creates the destination URL the
    /// downloaded file will be moved to.
    /// 行啊请求成功创建转存目录后回调
    func request(_ request: DownloadRequest, didCreateDestinationURL url: URL)

    /// Event called when a `DownloadRequest` calls a `Validation`.
    /// 行啊请求检测有效性成功
    func request(_ request: DownloadRequest,
                 didValidateRequest urlRequest: URLRequest?,
                 response: HTTPURLResponse,
                 fileURL: URL?,
                 withResult result: Request.ValidationResult)

    /// Event called when a `DownloadRequest` creates a `DownloadResponse<URL?, AFError>` without calling a `ResponseSerializer`.
    /// 使用原数据解析响应成功, 没有序列化
    func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>)

    /// Event called when a `DownloadRequest` calls a `DownloadResponseSerializer` and creates a generic `DownloadResponse<Value, AFError>`
    /// 序列化解析响应成功
    func request<Value>(_ request: DownloadRequest, didParseResponse response: DownloadResponse<Value, AFError>)
}

// 空实现
extension EventMonitor {
    /// The default queue on which `CompositeEventMonitor`s will call the `EventMonitor` methods. `.main` by default.
    public var queue: DispatchQueue { .main }

    // MARK: Default Implementations

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didReceive challenge: URLAuthenticationChallenge) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {}
    public func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didFinishCollecting metrics: URLSessionTaskMetrics) {}
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {}
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {}
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {}
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           willCacheResponse proposedResponse: CachedURLResponse) {}
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didResumeAtOffset fileOffset: Int64,
                           expectedTotalBytes: Int64) {}
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {}
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {}
    public func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest) {}
    public func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError) {}
    public func request(_ request: Request,
                        didAdaptInitialRequest initialRequest: URLRequest,
                        to adaptedRequest: URLRequest) {}
    public func request(_ request: Request,
                        didFailToAdaptURLRequest initialRequest: URLRequest,
                        withError error: AFError) {}
    public func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {}
    public func request(_ request: Request, didCreateTask task: URLSessionTask) {}
    public func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics) {}
    public func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError) {}
    public func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {}
    public func requestIsRetrying(_ request: Request) {}
    public func requestDidFinish(_ request: Request) {}
    public func requestDidResume(_ request: Request) {}
    public func request(_ request: Request, didResumeTask task: URLSessionTask) {}
    public func requestDidSuspend(_ request: Request) {}
    public func request(_ request: Request, didSuspendTask task: URLSessionTask) {}
    public func requestDidCancel(_ request: Request) {}
    public func request(_ request: Request, didCancelTask task: URLSessionTask) {}
    public func request(_ request: DataRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        data: Data?,
                        withResult result: Request.ValidationResult) {}
    public func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {}
    public func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {}
    public func request(_ request: DataStreamRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        withResult result: Request.ValidationResult) {}
    public func request<Value>(_ request: DataStreamRequest, didParseStream result: Result<Value, AFError>) {}
    public func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable) {}
    public func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError) {}
    public func request(_ request: UploadRequest, didProvideInputStream stream: InputStream) {}
    public func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>) {}
    public func request(_ request: DownloadRequest, didCreateDestinationURL url: URL) {}
    public func request(_ request: DownloadRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        fileURL: URL?,
                        withResult result: Request.ValidationResult) {}
    public func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>) {}
    public func request<Value>(_ request: DownloadRequest, didParseResponse response: DownloadResponse<Value, AFError>) {}
}

/// An `EventMonitor` which can contain multiple `EventMonitor`s and calls their methods on their queues.
/// 组合监听器
public final class CompositeEventMonitor: EventMonitor {
    // 异步队列
    public let queue = DispatchQueue(label: "org.alamofire.compositeEventMonitor", qos: .utility)
    // 监听器数组初始化, 持有这些数组
    let monitors: [EventMonitor]

    init(monitors: [EventMonitor]) {
        self.monitors = monitors
    }
    // 定义一个performEvent 方法用了派发回调
    func performEvent(_ event: @escaping (EventMonitor) -> Void) {
        // 在自己队列中, 异步循环, 在每个监听器各自的队列回调方法
        queue.async {
            for monitor in self.monitors {
                monitor.queue.async { event(monitor) }
            }
        }
    }

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        performEvent { $0.urlSession(session, didBecomeInvalidWithError: error) }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didReceive challenge: URLAuthenticationChallenge) {
        performEvent { $0.urlSession(session, task: task, didReceive: challenge) }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {
        performEvent {
            $0.urlSession(session,
                          task: task,
                          didSendBodyData: bytesSent,
                          totalBytesSent: totalBytesSent,
                          totalBytesExpectedToSend: totalBytesExpectedToSend)
        }
    }

    public func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask) {
        performEvent {
            $0.urlSession(session, taskNeedsNewBodyStream: task)
        }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) {
        performEvent {
            $0.urlSession(session,
                          task: task,
                          willPerformHTTPRedirection: response,
                          newRequest: request)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        performEvent { $0.urlSession(session, task: task, didFinishCollecting: metrics) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        performEvent { $0.urlSession(session, task: task, didCompleteWithError: error) }
    }

    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        performEvent { $0.urlSession(session, taskIsWaitingForConnectivity: task) }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        performEvent { $0.urlSession(session, dataTask: dataTask, didReceive: data) }
    }

    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           willCacheResponse proposedResponse: CachedURLResponse) {
        performEvent { $0.urlSession(session, dataTask: dataTask, willCacheResponse: proposedResponse) }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didResumeAtOffset fileOffset: Int64,
                           expectedTotalBytes: Int64) {
        performEvent {
            $0.urlSession(session,
                          downloadTask: downloadTask,
                          didResumeAtOffset: fileOffset,
                          expectedTotalBytes: expectedTotalBytes)
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        performEvent {
            $0.urlSession(session,
                          downloadTask: downloadTask,
                          didWriteData: bytesWritten,
                          totalBytesWritten: totalBytesWritten,
                          totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        performEvent { $0.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location) }
    }

    public func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest) {
        performEvent { $0.request(request, didCreateInitialURLRequest: urlRequest) }
    }

    public func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError) {
        performEvent { $0.request(request, didFailToCreateURLRequestWithError: error) }
    }

    public func request(_ request: Request, didAdaptInitialRequest initialRequest: URLRequest, to adaptedRequest: URLRequest) {
        performEvent { $0.request(request, didAdaptInitialRequest: initialRequest, to: adaptedRequest) }
    }

    public func request(_ request: Request, didFailToAdaptURLRequest initialRequest: URLRequest, withError error: AFError) {
        performEvent { $0.request(request, didFailToAdaptURLRequest: initialRequest, withError: error) }
    }

    public func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        performEvent { $0.request(request, didCreateURLRequest: urlRequest) }
    }

    public func request(_ request: Request, didCreateTask task: URLSessionTask) {
        performEvent { $0.request(request, didCreateTask: task) }
    }

    public func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics) {
        performEvent { $0.request(request, didGatherMetrics: metrics) }
    }

    public func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError) {
        performEvent { $0.request(request, didFailTask: task, earlyWithError: error) }
    }

    public func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {
        performEvent { $0.request(request, didCompleteTask: task, with: error) }
    }

    public func requestIsRetrying(_ request: Request) {
        performEvent { $0.requestIsRetrying(request) }
    }

    public func requestDidFinish(_ request: Request) {
        performEvent { $0.requestDidFinish(request) }
    }

    public func requestDidResume(_ request: Request) {
        performEvent { $0.requestDidResume(request) }
    }

    public func request(_ request: Request, didResumeTask task: URLSessionTask) {
        performEvent { $0.request(request, didResumeTask: task) }
    }

    public func requestDidSuspend(_ request: Request) {
        performEvent { $0.requestDidSuspend(request) }
    }

    public func request(_ request: Request, didSuspendTask task: URLSessionTask) {
        performEvent { $0.request(request, didSuspendTask: task) }
    }

    public func requestDidCancel(_ request: Request) {
        performEvent { $0.requestDidCancel(request) }
    }

    public func request(_ request: Request, didCancelTask task: URLSessionTask) {
        performEvent { $0.request(request, didCancelTask: task) }
    }

    public func request(_ request: DataRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        data: Data?,
                        withResult result: Request.ValidationResult) {
        performEvent { $0.request(request,
                                  didValidateRequest: urlRequest,
                                  response: response,
                                  data: data,
                                  withResult: result)
        }
    }

    public func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }

    public func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }

    public func request(_ request: DataStreamRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        withResult result: Request.ValidationResult) {
        performEvent { $0.request(request,
                                  didValidateRequest: urlRequest,
                                  response: response,
                                  withResult: result)
        }
    }

    public func request<Value>(_ request: DataStreamRequest, didParseStream result: Result<Value, AFError>) {
        performEvent { $0.request(request, didParseStream: result) }
    }

    public func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable) {
        performEvent { $0.request(request, didCreateUploadable: uploadable) }
    }

    public func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError) {
        performEvent { $0.request(request, didFailToCreateUploadableWithError: error) }
    }

    public func request(_ request: UploadRequest, didProvideInputStream stream: InputStream) {
        performEvent { $0.request(request, didProvideInputStream: stream) }
    }

    public func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>) {
        performEvent { $0.request(request, didFinishDownloadingUsing: task, with: result) }
    }

    public func request(_ request: DownloadRequest, didCreateDestinationURL url: URL) {
        performEvent { $0.request(request, didCreateDestinationURL: url) }
    }

    public func request(_ request: DownloadRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        fileURL: URL?,
                        withResult result: Request.ValidationResult) {
        performEvent { $0.request(request,
                                  didValidateRequest: urlRequest,
                                  response: response,
                                  fileURL: fileURL,
                                  withResult: result) }
    }

    public func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }

    public func request<Value>(_ request: DownloadRequest, didParseResponse response: DownloadResponse<Value, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }
}

/// `EventMonitor` that allows optional closures to be set to receive events.
/// 闭包监听器
/// queue 主队列
/// 持有N 多个闭包, N 为EventMonitor 接口的方法数, 一一对应
/// 每个协议的视线都会调用对应闭包
open class ClosureEventMonitor: EventMonitor {
    /// Closure called on the `urlSession(_:didBecomeInvalidWithError:)` event.
    open var sessionDidBecomeInvalidWithError: ((URLSession, Error?) -> Void)?

    /// Closure called on the `urlSession(_:task:didReceive:completionHandler:)`.
    open var taskDidReceiveChallenge: ((URLSession, URLSessionTask, URLAuthenticationChallenge) -> Void)?

    /// Closure that receives `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` event.
    open var taskDidSendBodyData: ((URLSession, URLSessionTask, Int64, Int64, Int64) -> Void)?

    /// Closure called on the `urlSession(_:task:needNewBodyStream:)` event.
    open var taskNeedNewBodyStream: ((URLSession, URLSessionTask) -> Void)?

    /// Closure called on the `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` event.
    open var taskWillPerformHTTPRedirection: ((URLSession, URLSessionTask, HTTPURLResponse, URLRequest) -> Void)?

    /// Closure called on the `urlSession(_:task:didFinishCollecting:)` event.
    open var taskDidFinishCollectingMetrics: ((URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void)?

    /// Closure called on the `urlSession(_:task:didCompleteWithError:)` event.
    open var taskDidComplete: ((URLSession, URLSessionTask, Error?) -> Void)?

    /// Closure called on the `urlSession(_:taskIsWaitingForConnectivity:)` event.
    open var taskIsWaitingForConnectivity: ((URLSession, URLSessionTask) -> Void)?

    /// Closure that receives the `urlSession(_:dataTask:didReceive:)` event.
    open var dataTaskDidReceiveData: ((URLSession, URLSessionDataTask, Data) -> Void)?

    /// Closure called on the `urlSession(_:dataTask:willCacheResponse:completionHandler:)` event.
    open var dataTaskWillCacheResponse: ((URLSession, URLSessionDataTask, CachedURLResponse) -> Void)?

    /// Closure called on the `urlSession(_:downloadTask:didFinishDownloadingTo:)` event.
    open var downloadTaskDidFinishDownloadingToURL: ((URLSession, URLSessionDownloadTask, URL) -> Void)?

    /// Closure called on the `urlSession(_:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)`
    /// event.
    open var downloadTaskDidWriteData: ((URLSession, URLSessionDownloadTask, Int64, Int64, Int64) -> Void)?

    /// Closure called on the `urlSession(_:downloadTask:didResumeAtOffset:expectedTotalBytes:)` event.
    open var downloadTaskDidResumeAtOffset: ((URLSession, URLSessionDownloadTask, Int64, Int64) -> Void)?

    // MARK: - Request Events

    /// Closure called on the `request(_:didCreateInitialURLRequest:)` event.
    open var requestDidCreateInitialURLRequest: ((Request, URLRequest) -> Void)?

    /// Closure called on the `request(_:didFailToCreateURLRequestWithError:)` event.
    open var requestDidFailToCreateURLRequestWithError: ((Request, AFError) -> Void)?

    /// Closure called on the `request(_:didAdaptInitialRequest:to:)` event.
    open var requestDidAdaptInitialRequestToAdaptedRequest: ((Request, URLRequest, URLRequest) -> Void)?

    /// Closure called on the `request(_:didFailToAdaptURLRequest:withError:)` event.
    open var requestDidFailToAdaptURLRequestWithError: ((Request, URLRequest, AFError) -> Void)?

    /// Closure called on the `request(_:didCreateURLRequest:)` event.
    open var requestDidCreateURLRequest: ((Request, URLRequest) -> Void)?

    /// Closure called on the `request(_:didCreateTask:)` event.
    open var requestDidCreateTask: ((Request, URLSessionTask) -> Void)?

    /// Closure called on the `request(_:didGatherMetrics:)` event.
    open var requestDidGatherMetrics: ((Request, URLSessionTaskMetrics) -> Void)?

    /// Closure called on the `request(_:didFailTask:earlyWithError:)` event.
    open var requestDidFailTaskEarlyWithError: ((Request, URLSessionTask, AFError) -> Void)?

    /// Closure called on the `request(_:didCompleteTask:with:)` event.
    open var requestDidCompleteTaskWithError: ((Request, URLSessionTask, AFError?) -> Void)?

    /// Closure called on the `requestIsRetrying(_:)` event.
    open var requestIsRetrying: ((Request) -> Void)?

    /// Closure called on the `requestDidFinish(_:)` event.
    open var requestDidFinish: ((Request) -> Void)?

    /// Closure called on the `requestDidResume(_:)` event.
    open var requestDidResume: ((Request) -> Void)?

    /// Closure called on the `request(_:didResumeTask:)` event.
    open var requestDidResumeTask: ((Request, URLSessionTask) -> Void)?

    /// Closure called on the `requestDidSuspend(_:)` event.
    open var requestDidSuspend: ((Request) -> Void)?

    /// Closure called on the `request(_:didSuspendTask:)` event.
    open var requestDidSuspendTask: ((Request, URLSessionTask) -> Void)?

    /// Closure called on the `requestDidCancel(_:)` event.
    open var requestDidCancel: ((Request) -> Void)?

    /// Closure called on the `request(_:didCancelTask:)` event.
    open var requestDidCancelTask: ((Request, URLSessionTask) -> Void)?

    /// Closure called on the `request(_:didValidateRequest:response:data:withResult:)` event.
    open var requestDidValidateRequestResponseDataWithResult: ((DataRequest, URLRequest?, HTTPURLResponse, Data?, Request.ValidationResult) -> Void)?

    /// Closure called on the `request(_:didParseResponse:)` event.
    open var requestDidParseResponse: ((DataRequest, DataResponse<Data?, AFError>) -> Void)?

    /// Closure called on the `request(_:didValidateRequest:response:withResult:)` event.
    open var requestDidValidateRequestResponseWithResult: ((DataStreamRequest, URLRequest?, HTTPURLResponse, Request.ValidationResult) -> Void)?

    /// Closure called on the `request(_:didCreateUploadable:)` event.
    open var requestDidCreateUploadable: ((UploadRequest, UploadRequest.Uploadable) -> Void)?

    /// Closure called on the `request(_:didFailToCreateUploadableWithError:)` event.
    open var requestDidFailToCreateUploadableWithError: ((UploadRequest, AFError) -> Void)?

    /// Closure called on the `request(_:didProvideInputStream:)` event.
    open var requestDidProvideInputStream: ((UploadRequest, InputStream) -> Void)?

    /// Closure called on the `request(_:didFinishDownloadingUsing:with:)` event.
    open var requestDidFinishDownloadingUsingTaskWithResult: ((DownloadRequest, URLSessionTask, Result<URL, AFError>) -> Void)?

    /// Closure called on the `request(_:didCreateDestinationURL:)` event.
    open var requestDidCreateDestinationURL: ((DownloadRequest, URL) -> Void)?

    /// Closure called on the `request(_:didValidateRequest:response:temporaryURL:destinationURL:withResult:)` event.
    open var requestDidValidateRequestResponseFileURLWithResult: ((DownloadRequest, URLRequest?, HTTPURLResponse, URL?, Request.ValidationResult) -> Void)?

    /// Closure called on the `request(_:didParseResponse:)` event.
    open var requestDidParseDownloadResponse: ((DownloadRequest, DownloadResponse<URL?, AFError>) -> Void)?

    public let queue: DispatchQueue

    /// Creates an instance using the provided queue.
    ///
    /// - Parameter queue: `DispatchQueue` on which events will fired. `.main` by default.
    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    open func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        sessionDidBecomeInvalidWithError?(session, error)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) {
        taskDidReceiveChallenge?(session, task, challenge)
    }

    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         didSendBodyData bytesSent: Int64,
                         totalBytesSent: Int64,
                         totalBytesExpectedToSend: Int64) {
        taskDidSendBodyData?(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
    }

    open func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask) {
        taskNeedNewBodyStream?(session, task)
    }

    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest) {
        taskWillPerformHTTPRedirection?(session, task, response, request)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        taskDidFinishCollectingMetrics?(session, task, metrics)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        taskDidComplete?(session, task, error)
    }

    open func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        taskIsWaitingForConnectivity?(session, task)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataTaskDidReceiveData?(session, dataTask, data)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse) {
        dataTaskWillCacheResponse?(session, dataTask, proposedResponse)
    }

    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didResumeAtOffset fileOffset: Int64,
                         expectedTotalBytes: Int64) {
        downloadTaskDidResumeAtOffset?(session, downloadTask, fileOffset, expectedTotalBytes)
    }

    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64,
                         totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
        downloadTaskDidWriteData?(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }

    open func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        downloadTaskDidFinishDownloadingToURL?(session, downloadTask, location)
    }

    // MARK: Request Events

    open func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest) {
        requestDidCreateInitialURLRequest?(request, urlRequest)
    }

    open func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError) {
        requestDidFailToCreateURLRequestWithError?(request, error)
    }

    open func request(_ request: Request, didAdaptInitialRequest initialRequest: URLRequest, to adaptedRequest: URLRequest) {
        requestDidAdaptInitialRequestToAdaptedRequest?(request, initialRequest, adaptedRequest)
    }

    open func request(_ request: Request, didFailToAdaptURLRequest initialRequest: URLRequest, withError error: AFError) {
        requestDidFailToAdaptURLRequestWithError?(request, initialRequest, error)
    }

    open func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        requestDidCreateURLRequest?(request, urlRequest)
    }

    open func request(_ request: Request, didCreateTask task: URLSessionTask) {
        requestDidCreateTask?(request, task)
    }

    open func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics) {
        requestDidGatherMetrics?(request, metrics)
    }

    open func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError) {
        requestDidFailTaskEarlyWithError?(request, task, error)
    }

    open func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {
        requestDidCompleteTaskWithError?(request, task, error)
    }

    open func requestIsRetrying(_ request: Request) {
        requestIsRetrying?(request)
    }

    open func requestDidFinish(_ request: Request) {
        requestDidFinish?(request)
    }

    open func requestDidResume(_ request: Request) {
        requestDidResume?(request)
    }

    public func request(_ request: Request, didResumeTask task: URLSessionTask) {
        requestDidResumeTask?(request, task)
    }

    open func requestDidSuspend(_ request: Request) {
        requestDidSuspend?(request)
    }

    public func request(_ request: Request, didSuspendTask task: URLSessionTask) {
        requestDidSuspendTask?(request, task)
    }

    open func requestDidCancel(_ request: Request) {
        requestDidCancel?(request)
    }

    public func request(_ request: Request, didCancelTask task: URLSessionTask) {
        requestDidCancelTask?(request, task)
    }

    open func request(_ request: DataRequest,
                      didValidateRequest urlRequest: URLRequest?,
                      response: HTTPURLResponse,
                      data: Data?,
                      withResult result: Request.ValidationResult) {
        requestDidValidateRequestResponseDataWithResult?(request, urlRequest, response, data, result)
    }

    open func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {
        requestDidParseResponse?(request, response)
    }

    public func request(_ request: DataStreamRequest, didValidateRequest urlRequest: URLRequest?, response: HTTPURLResponse, withResult result: Request.ValidationResult) {
        requestDidValidateRequestResponseWithResult?(request, urlRequest, response, result)
    }

    open func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable) {
        requestDidCreateUploadable?(request, uploadable)
    }

    open func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError) {
        requestDidFailToCreateUploadableWithError?(request, error)
    }

    open func request(_ request: UploadRequest, didProvideInputStream stream: InputStream) {
        requestDidProvideInputStream?(request, stream)
    }

    open func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>) {
        requestDidFinishDownloadingUsingTaskWithResult?(request, task, result)
    }

    open func request(_ request: DownloadRequest, didCreateDestinationURL url: URL) {
        requestDidCreateDestinationURL?(request, url)
    }

    open func request(_ request: DownloadRequest,
                      didValidateRequest urlRequest: URLRequest?,
                      response: HTTPURLResponse,
                      fileURL: URL?,
                      withResult result: Request.ValidationResult) {
        requestDidValidateRequestResponseFileURLWithResult?(request,
                                                            urlRequest,
                                                            response,
                                                            fileURL,
                                                            result)
    }

    open func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>) {
        requestDidParseDownloadResponse?(request, response)
    }
}
