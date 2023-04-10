//
//  SessionDelegate.swift
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

/// Class which implements the various `URLSessionDelegate` methods to connect various Alamofire features.
/// 实现URLSessionDelegate 以及各个URLSessionTaskDelegate 并派发时间监听器对象
open class SessionDelegate: NSObject {
    private let fileManager: FileManager
    // 指向Session, 从Session 中从Request-Task 获取Task 对应的Request 对象
    weak var stateProvider: SessionStateProvider?
    // 强引用EventMonitor 协议对象, 用来接收请求中的各个状态事件
    var eventMonitor: EventMonitor?

    /// Creates an instance from the given `FileManager`.
    ///
    /// - Parameter fileManager: `FileManager` to use for underlying file management, such as moving downloaded files.
    ///                          `.default` by default.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Internal method to find and cast requests while maintaining some integrity checking.
    ///
    /// - Parameters:
    ///   - task: The `URLSessionTask` for which to find the associated `Request`.
    ///   - type: The `Request` subclass type to cast any `Request` associate with `task`.
    /// 根据Task 获取对应Request, 转成对应子类
    func request<R: Request>(for task: URLSessionTask, as type: R.Type) -> R? {
        guard let provider = stateProvider else {
            assertionFailure("StateProvider is nil.")
            return nil
        }
        // 从SessionStateProvider(Session) 中根据task 获取request
        return provider.request(for: task) as? R
    }
}

/// Type which provides various `Session` state values.
/// 定义SessionStateProvider协议, Session 实现了该协议, 连接Session 和SessionDelegate
protocol SessionStateProvider: AnyObject {
    // 从Session 中获取证书管理器, 重定向管理器, 缓存管理器
    var serverTrustManager: ServerTrustManager? { get }
    var redirectHandler: RedirectHandler? { get }
    var cachedResponseHandler: CachedResponseHandler? { get }
    // 从Session 的RequestTaskMap 中根据task 中获取request
    func request(for task: URLSessionTask) -> Request?
    // 获取任务后的回调
    func didGatherMetricsForTask(_ task: URLSessionTask)
    // 获取完成后的回调, 后续可能会处理其他任务
    func didCompleteTask(_ task: URLSessionTask, completion: @escaping () -> Void)
    // 认证授权处理
    func credential(for task: URLSessionTask, in protectionSpace: URLProtectionSpace) -> URLCredential?
    // Session 失效的回调
    func cancelRequestsForSessionInvalidation(with error: Error?)
}

// MARK: URLSessionDelegate

extension SessionDelegate: URLSessionDelegate {
    open func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        // Session 不可用, 通知监听器, 回调Session 取消全部请求
        eventMonitor?.urlSession(session, didBecomeInvalidWithError: error)
        stateProvider?.cancelRequestsForSessionInvalidation(with: error)
    }
}

// MARK: URLSessionTaskDelegate

extension SessionDelegate: URLSessionTaskDelegate {
    /// Result of a `URLAuthenticationChallenge` evaluation.
    /// 定义元组包裹认证处理方式, 证书, 以及错误
    typealias ChallengeEvaluation = (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?, error: AFError?)
    
    // 收到需要验证证书的回调
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         didReceive challenge: URLAuthenticationChallenge,
                         completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // 告知事件监听器
        eventMonitor?.urlSession(session, task: task, didReceive: challenge)

        let evaluation: ChallengeEvaluation
        // 组装认证方式, 证书, 错误信息
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM,
             NSURLAuthenticationMethodNegotiate:
            // 其他认证方式
            evaluation = attemptCredentialAuthentication(for: challenge, belongingTo: task)
        #if !(os(Linux) || os(Windows))
        case NSURLAuthenticationMethodServerTrust:
            // https 认证
            evaluation = attemptServerTrustAuthentication(with: challenge)
        case NSURLAuthenticationMethodClientCertificate:
            evaluation = attemptCredentialAuthentication(for: challenge, belongingTo: task)
        #endif
        default:
            evaluation = (.performDefaultHandling, nil, nil)
        }
        // 获取证书失败, 该请求失败, 传递出错误
        if let error = evaluation.error {
            stateProvider?.request(for: task)?.didFailTask(task, earlyWithError: error)
        }
        // 结果回调
        completionHandler(evaluation.disposition, evaluation.credential)
    }

    #if !(os(Linux) || os(Windows))
    /// Evaluates the server trust `URLAuthenticationChallenge` received.
    ///
    /// - Parameter challenge: The `URLAuthenticationChallenge`.
    ///
    /// - Returns:             The `ChallengeEvaluation`.
    /// 处理服务器认证
    func attemptServerTrustAuthentication(with challenge: URLAuthenticationChallenge) -> ChallengeEvaluation {
        let host = challenge.protectionSpace.host

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            // 没有自定义证书管理器, 直接返回默认处理
            return (.performDefaultHandling, nil, nil)
        }

        do {
            guard let evaluator = try stateProvider?.serverTrustManager?.serverTrustEvaluator(forHost: host) else {
                return (.performDefaultHandling, nil, nil)
            }
            // 从ServerTrustManager 中取到ServerTrustEvaluating 对象, 执行自定义认证
            try evaluator.evaluate(trust, forHost: host)

            return (.useCredential, URLCredential(trust: trust), nil)
        } catch {
            // 自定义认证出错, 返回取消认证操作, 和错误信息
            return (.cancelAuthenticationChallenge, nil, error.asAFError(or: .serverTrustEvaluationFailed(reason: .customEvaluationFailed(error: error))))
        }
    }
    #endif

    /// Evaluates the credential-based authentication `URLAuthenticationChallenge` received for `task`.
    ///
    /// - Parameters:
    ///   - challenge: The `URLAuthenticationChallenge`.
    ///   - task:      The `URLSessionTask` which received the challenge.
    ///
    /// - Returns:     The `ChallengeEvaluation`.
    /// 其他认证方式
    func attemptCredentialAuthentication(for challenge: URLAuthenticationChallenge,
                                         belongingTo task: URLSessionTask) -> ChallengeEvaluation {
        guard challenge.previousFailureCount == 0 else {
            // 如果之前认证失败, 直接跳过本次认证, 开始下一次认证
            return (.rejectProtectionSpace, nil, nil)
        }

        guard let credential = stateProvider?.credential(for: task, in: challenge.protectionSpace) else {
            // 没有获取到认证处理对象, 忽略本次认证
            return (.performDefaultHandling, nil, nil)
        }

        return (.useCredential, credential, nil)
    }
    // 上传进度
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         didSendBodyData bytesSent: Int64,
                         totalBytesSent: Int64,
                         totalBytesExpectedToSend: Int64) {
        // 通知监听器
        eventMonitor?.urlSession(session,
                                 task: task,
                                 didSendBodyData: bytesSent,
                                 totalBytesSent: totalBytesSent,
                                 totalBytesExpectedToSend: totalBytesExpectedToSend)
        // 拿到Request 更新上传监督
        stateProvider?.request(for: task)?.updateUploadProgress(totalBytesSent: totalBytesSent,
                                                                totalBytesExpectedToSend: totalBytesExpectedToSend)
    }
    // 上传请求转吧上传新的body 流
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        // 通知事件监听器
        eventMonitor?.urlSession(session, taskNeedsNewBodyStream: task)
        
        guard let request = request(for: task, as: UploadRequest.self) else {
            // 只有上传请求会响应这个方法
            assertionFailure("needNewBodyStream did not find UploadRequest.")
            completionHandler(nil)
            return
        }
        // 从request 中拿到InputStream 返回, 只有使用InputStream 创建的上传请求才会返回正确, 否则抛出错误
        completionHandler(request.inputStream())
    }
    // 重定向
    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest,
                         completionHandler: @escaping (URLRequest?) -> Void) {
        // 通知事件监听器
        eventMonitor?.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request)

        if let redirectHandler = stateProvider?.request(for: task)?.redirectHandler ?? stateProvider?.redirectHandler {
            // 先看Request 有没有自己的重定向处理器, 再看Session 有没有全局重定向处理器, 有就处理
            redirectHandler.task(task, willBeRedirectedTo: request, for: response, completion: completionHandler)
        } else {
            completionHandler(request)
        }
    }
    // 获取请求指标
    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        // 通知事件监听器
        eventMonitor?.urlSession(session, task: task, didFinishCollecting: metrics)
        // 通知Request
        stateProvider?.request(for: task)?.didGatherMetrics(metrics)
        // 通知Session
        stateProvider?.didGatherMetricsForTask(task)
    }
    // 请求完成, 后续可能回去获取网页指标
    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 通知监听器
        eventMonitor?.urlSession(session, task: task, didCompleteWithError: error)
        
        let request = stateProvider?.request(for: task)
        // 通知Session 请求完成
        stateProvider?.didCompleteTask(task) {
            // 回调内容为 确认请求指标完成后, 通知Request 请求完成
            request?.didCompleteTask(task, with: error.map { $0.asAFError(or: .sessionTaskFailed(error: $0)) })
        }
    }

    // 网络变更导致的请求等待处理
    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        eventMonitor?.urlSession(session, taskIsWaitingForConnectivity: task)
    }
}

// MARK: URLSessionDataDelegate
extension SessionDelegate: URLSessionDataDelegate {
    // 收到响应请求
    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // 通知监听器
        eventMonitor?.urlSession(session, dataTask: dataTask, didReceive: data)
        // 只有DataRequest 跟DataStreamRequest 会收到数据
        if let request = request(for: dataTask, as: DataRequest.self) {
            request.didReceive(data: data)
        } else if let request = request(for: dataTask, as: DataStreamRequest.self) {
            request.didReceive(data: data)
        } else {
            assertionFailure("dataTask did not find DataRequest or DataStreamRequest in didReceive")
            return
        }
    }
    // 是否保存缓存
    open func urlSession(_ session: URLSession,
                         dataTask: URLSessionDataTask,
                         willCacheResponse proposedResponse: CachedURLResponse,
                         completionHandler: @escaping (CachedURLResponse?) -> Void) {
        // 通知监听器
        eventMonitor?.urlSession(session, dataTask: dataTask, willCacheResponse: proposedResponse)

        if let handler = stateProvider?.request(for: dataTask)?.cachedResponseHandler ?? stateProvider?.cachedResponseHandler {
            // 用request 的缓存处理器处理缓存
            handler.dataTask(dataTask, willCacheResponse: proposedResponse, completion: completionHandler)
        } else {
            completionHandler(proposedResponse)
        }
    }
}

// MARK: URLSessionDownloadDelegate

extension SessionDelegate: URLSessionDownloadDelegate {
    // 开始断点续传的回调
    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didResumeAtOffset fileOffset: Int64,
                         expectedTotalBytes: Int64) {
        // 通知监听器
        eventMonitor?.urlSession(session,
                                 downloadTask: downloadTask,
                                 didResumeAtOffset: fileOffset,
                                 expectedTotalBytes: expectedTotalBytes)
        guard let downloadRequest = request(for: downloadTask, as: DownloadRequest.self) else {
            assertionFailure("downloadTask did not find DownloadRequest.")
            return
        }

        downloadRequest.updateDownloadProgress(bytesWritten: fileOffset,
                                               totalBytesExpectedToWrite: expectedTotalBytes)
    }
    // 更新下载进度
    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64,
                         totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
        // 通知监听器
        eventMonitor?.urlSession(session,
                                 downloadTask: downloadTask,
                                 didWriteData: bytesWritten,
                                 totalBytesWritten: totalBytesWritten,
                                 totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        guard let downloadRequest = request(for: downloadTask, as: DownloadRequest.self) else {
            assertionFailure("downloadTask did not find DownloadRequest.")
            return
        }

        downloadRequest.updateDownloadProgress(bytesWritten: bytesWritten,
                                               totalBytesExpectedToWrite: totalBytesExpectedToWrite)
    }
    // 下载完成
    open func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 事件监听器
        eventMonitor?.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
        
        guard let request = request(for: downloadTask, as: DownloadRequest.self) else {
            assertionFailure("downloadTask did not find DownloadRequest.")
            return
        }
        // 准备转存文件, 定义元组, 转存目录, 下载options
        let (destination, options): (URL, DownloadRequest.Options)
        if let response = request.response {
            // 从request 拿到转存目录
            (destination, options) = request.destination(location, response)
        } else {
            // If there's no response this is likely a local file download, so generate the temporary URL directly.
            (destination, options) = (DownloadRequest.defaultDestinationURL(location), [])
        }
        // 通知事件监听器
        eventMonitor?.request(request, didCreateDestinationURL: destination)

        do {
            // 是否删除旧文件
            if options.contains(.removePreviousFile), fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // 是否创建目录链
            if options.contains(.createIntermediateDirectories) {
                let directory = destination.deletingLastPathComponent()
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            // 转存文件
            try fileManager.moveItem(at: location, to: destination)
            // 回调给request
            request.didFinishDownloading(using: downloadTask, with: .success(destination))
        } catch {
            // 出错抛出异常
            request.didFinishDownloading(using: downloadTask, with: .failure(.downloadedFileMoveFailed(error: error,
                                                                                                       source: location,
                                                                                                       destination: destination)))
        }
    }
}
