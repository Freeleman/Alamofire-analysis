//
//  ServerTrustPolicy.swift
//
//  Copyright (c) 2014-2016 Alamofire Software Foundation (http://alamofire.org/)
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

/// Responsible for managing the mapping of `ServerTrustEvaluating` values to given hosts.
open class ServerTrustManager {
    /// Determines whether all hosts for this `ServerTrustManager` must be evaluated. `true` by default.
    /// 是否所有的域名都需要认证, 默认为true
    /// 若为true, 每个host 都要有对应的认证器存在,否则会抛出异常
    /// 若为false, 当某个host 没有对应的认证器时, 返回nil, 不抛出错误
    public let allHostsMustBeEvaluated: Bool

    /// The dictionary of policies mapped to a particular host.
    /// 保存host 与认证器的映射
    public let evaluators: [String: ServerTrustEvaluating]

    /// Initializes the `ServerTrustManager` instance with the given evaluators.
    ///
    /// Since different servers and web services can have different leaf certificates, intermediate and even root
    /// certificates, it is important to have the flexibility to specify evaluation policies on a per host basis. This
    /// allows for scenarios such as using default evaluation for host1, certificate pinning for host2, public key
    /// pinning for host3 and disabling evaluation for host4.
    ///
    /// - Parameters:
    ///   - allHostsMustBeEvaluated: The value determining whether all hosts for this instance must be evaluated. `true`
    ///                              by default.
    ///   - evaluators:              A dictionary of evaluators mapped to hosts.
    ///   初始化, 由于不同的服务区可能会有不同的认证方式, 所以管理的认证方式是基于域名的
    public init(allHostsMustBeEvaluated: Bool = true, evaluators: [String: ServerTrustEvaluating]) {
        self.allHostsMustBeEvaluated = allHostsMustBeEvaluated
        self.evaluators = evaluators
    }

    #if !(os(Linux) || os(Windows))
    /// Returns the `ServerTrustEvaluating` value for the given host, if one is set.
    ///
    /// By default, this method will return the policy that perfectly matches the given host. Subclasses could override
    /// this method and implement more complex mapping implementations such as wildcards.
    ///
    /// - Parameter host: The host to use when searching for a matching policy.
    ///
    /// - Returns:        The `ServerTrustEvaluating` value for the given host if found, `nil` otherwise.
    /// - Throws:         `AFError.serverTrustEvaluationFailed` if `allHostsMustBeEvaluated` is `true` and no matching
    ///                   evaluators are found.
    /// 根据域名返回对应的认证器, 可抛出错误
    open func serverTrustEvaluator(forHost host: String) throws -> ServerTrustEvaluating? {
        // 若设置了全部域名都要被认证, 当没有对应的认证器时, 就抛出错误
        guard let evaluator = evaluators[host] else {
            if allHostsMustBeEvaluated {
                throw AFError.serverTrustEvaluationFailed(reason: .noRequiredEvaluator(host: host))
            }

            return nil
        }

        return evaluator
    }
    #endif
}

/// A protocol describing the API used to evaluate server trusts.
public protocol ServerTrustEvaluating {
    #if os(Linux) || os(Windows)
    // Implement this once Linux/Windows has API for evaluating server trusts.
    #else
    /// Evaluates the given `SecTrust` value for the given `host`.
    ///
    /// - Parameters:
    ///   - trust: The `SecTrust` value to evaluate.
    ///   - host:  The host for which to evaluate the `SecTrust` value.
    ///
    /// - Returns: A `Bool` indicating whether the evaluator considers the `SecTrust` value valid for `host`.
    func evaluate(_ trust: SecTrust, forHost host: String) throws
    #endif
}

// MARK: - Server Trust Evaluators

#if !(os(Linux) || os(Windows))
/// An evaluator which uses the default server trust evaluation while allowing you to control whether to validate the
/// host provided by the challenge. Applications are encouraged to always validate the host in production environments
/// to guarantee the validity of the server's certificate chain.
public final class DefaultTrustEvaluator: ServerTrustEvaluating {
    private let validateHost: Bool

    /// Creates a `DefaultTrustEvaluator`.
    ///
    /// - Parameter validateHost: Determines whether or not the evaluator should validate the host. `true` by default.
    public init(validateHost: Bool = true) {
        self.validateHost = validateHost
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        if validateHost {
            try trust.af.performValidation(forHost: host)
        }

        try trust.af.performDefaultValidation(forHost: host)
    }
}

/// An evaluator which Uses the default and revoked server trust evaluations allowing you to control whether to validate
/// the host provided by the challenge as well as specify the revocation flags for testing for revoked certificates.
/// Apple platforms did not start testing for revoked certificates automatically until iOS 10.1, macOS 10.12 and tvOS
/// 10.1 which is demonstrated in our TLS tests. Applications are encouraged to always validate the host in production
/// environments to guarantee the validity of the server's certificate chain.
/// 是否证书被吊销
public final class RevocationTrustEvaluator: ServerTrustEvaluating {
    /// Represents the options to be use when evaluating the status of a certificate.
    /// Only Revocation Policy Constants are valid, and can be found in [Apple's documentation](https://developer.apple.com/documentation/security/certificate_key_and_trust_services/policies/1563600-revocation_policy_constants).
    public struct Options: OptionSet {
        /// Perform revocation checking using the CRL (Certification Revocation List) method.
        public static let crl = Options(rawValue: kSecRevocationCRLMethod)
        /// Consult only locally cached replies; do not use network access.
        public static let networkAccessDisabled = Options(rawValue: kSecRevocationNetworkAccessDisabled)
        /// Perform revocation checking using OCSP (Online Certificate Status Protocol).
        public static let ocsp = Options(rawValue: kSecRevocationOCSPMethod)
        /// Prefer CRL revocation checking over OCSP; by default, OCSP is preferred.
        public static let preferCRL = Options(rawValue: kSecRevocationPreferCRL)
        /// Require a positive response to pass the policy. If the flag is not set, revocation checking is done on a
        /// "best attempt" basis, where failure to reach the server is not considered fatal.
        public static let requirePositiveResponse = Options(rawValue: kSecRevocationRequirePositiveResponse)
        /// Perform either OCSP or CRL checking. The checking is performed according to the method(s) specified in the
        /// certificate and the value of `preferCRL`.
        public static let any = Options(rawValue: kSecRevocationUseAnyAvailableMethod)

        /// The raw value of the option.
        public let rawValue: CFOptionFlags

        /// Creates an `Options` value with the given `CFOptionFlags`.
        ///
        /// - Parameter rawValue: The `CFOptionFlags` value to initialize with.
        public init(rawValue: CFOptionFlags) {
            self.rawValue = rawValue
        }
    }
    // 是否需要进行默认安全校验, 默认true
    private let performDefaultValidation: Bool
    // 是否需要进行主机名验证, 默认true
    private let validateHost: Bool
    // 用来创建吊销证书校验安全策略的Options, 默认.any
    private let options: Options

    /// Creates a `RevocationTrustEvaluator` using the provided parameters.
    ///
    /// - Note: Default and host validation will fail when using this evaluator with self-signed certificates. Use
    ///         `PinnedCertificatesTrustEvaluator` if you need to use self-signed certificates.
    ///
    /// - Parameters:
    ///   - performDefaultValidation: Determines whether default validation should be performed in addition to
    ///                               evaluating the pinned certificates. `true` by default.
    ///   - validateHost:             Determines whether or not the evaluator should validate the host, in addition to
    ///                               performing the default evaluation, even if `performDefaultValidation` is `false`.
    ///                               `true` by default.
    ///   - options:                  The `Options` to use to check the revocation status of the certificate. `.any` by
    ///                               default.
    public init(performDefaultValidation: Bool = true, validateHost: Bool = true, options: Options = .any) {
        self.performDefaultValidation = performDefaultValidation
        self.validateHost = validateHost
        self.options = options
    }
    // 实现协议的校验方法
    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        // 需要进行默认校验, 调用方法先进行默认校验
        if performDefaultValidation {
            try trust.af.performDefaultValidation(forHost: host)
        }

        if validateHost {
            // 需要验证主机名
            try trust.af.performValidation(forHost: host)
        }
        // 需要使用吊销证书校验安全策略来进行评估, iOS12 上下分别用不同方法来进行校验
        if #available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, *) {
            try trust.af.evaluate(afterApplying: SecPolicy.af.revocation(options: options))
        } else {
            try trust.af.validate(policy: SecPolicy.af.revocation(options: options)) { status, result in
                AFError.serverTrustEvaluationFailed(reason: .revocationCheckFailed(output: .init(host, trust, status, result), options: options))
            }
        }
    }
}

#if swift(>=5.5)
extension ServerTrustEvaluating where Self == RevocationTrustEvaluator {
    /// Provides a default `RevocationTrustEvaluator` instance.
    public static var revocationChecking: RevocationTrustEvaluator { RevocationTrustEvaluator() }

    /// Creates a `RevocationTrustEvaluator` using the provided parameters.
    ///
    /// - Note: Default and host validation will fail when using this evaluator with self-signed certificates. Use
    ///         `PinnedCertificatesTrustEvaluator` if you need to use self-signed certificates.
    ///
    /// - Parameters:
    ///   - performDefaultValidation: Determines whether default validation should be performed in addition to
    ///                               evaluating the pinned certificates. `true` by default.
    ///   - validateHost:             Determines whether or not the evaluator should validate the host, in addition
    ///                               to performing the default evaluation, even if `performDefaultValidation` is
    ///                               `false`. `true` by default.
    ///   - options:                  The `Options` to use to check the revocation status of the certificate. `.any`
    ///                               by default.
    /// - Returns:                    The `RevocationTrustEvaluator`.
    public static func revocationChecking(performDefaultValidation: Bool = true,
                                          validateHost: Bool = true,
                                          options: RevocationTrustEvaluator.Options = .any) -> RevocationTrustEvaluator {
        RevocationTrustEvaluator(performDefaultValidation: performDefaultValidation,
                                 validateHost: validateHost,
                                 options: options)
    }
}
#endif

/// Uses the pinned certificates to validate the server trust. The server trust is considered valid if one of the pinned
/// certificates match one of the server certificates. By validating both the certificate chain and host, certificate
/// pinning provides a very secure form of server trust validation mitigating most, if not all, MITM attacks.
/// Applications are encouraged to always validate the host and require a valid certificate chain in production
/// environments.
/// 自定义证书校验器
/// 可以使用app 内置的自定义证书来对服务端证书进行校验, 可用于自签名证书验证.
public final class PinnedCertificatesTrustEvaluator: ServerTrustEvaluating {
    // 保存自定义证书, 默认为app 中所有的有效证书
    private let certificates: [SecCertificate]
    // 是否把自定义证书添加到校验的锚定证书中, 用来对自签名证书进行校验, 默认false
    private let acceptSelfSignedCertificates: Bool
    // 是否需要进行默认校验, 默认true
    private let performDefaultValidation: Bool
    // 是否验证主机名, 默认true
    private let validateHost: Bool

    /// Creates a `PinnedCertificatesTrustEvaluator` from the provided parameters.
    ///
    /// - Parameters:
    ///   - certificates:                 The certificates to use to evaluate the trust. All `cer`, `crt`, and `der`
    ///                                   certificates in `Bundle.main` by default.
    ///   - acceptSelfSignedCertificates: Adds the provided certificates as anchors for the trust evaluation, allowing
    ///                                   self-signed certificates to pass. `false` by default. THIS SETTING SHOULD BE
    ///                                   FALSE IN PRODUCTION!
    ///   - performDefaultValidation:     Determines whether default validation should be performed in addition to
    ///                                   evaluating the pinned certificates. `true` by default.
    ///   - validateHost:                 Determines whether or not the evaluator should validate the host, in addition
    ///                                   to performing the default evaluation, even if `performDefaultValidation` is
    ///                                   `false`. `true` by default.
    public init(certificates: [SecCertificate] = Bundle.main.af.certificates,
                acceptSelfSignedCertificates: Bool = false,
                performDefaultValidation: Bool = true,
                validateHost: Bool = true) {
        self.certificates = certificates
        self.acceptSelfSignedCertificates = acceptSelfSignedCertificates
        self.performDefaultValidation = performDefaultValidation
        self.validateHost = validateHost
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        // 如果自定义证书为空, 直接抛出错误
        guard !certificates.isEmpty else {
            throw AFError.serverTrustEvaluationFailed(reason: .noCertificatesFound)
        }

        if acceptSelfSignedCertificates {
            // 需要对自签名证书校验的话, 把自定义证书数组全部添加到SecTrust 中
            try trust.af.setAnchorCertificates(certificates)
        }

        if performDefaultValidation {
            // 执行默认校验
            try trust.af.performDefaultValidation(forHost: host)
        }

        if validateHost {
            // 执行主机名验证
            try trust.af.performValidation(forHost: host)
        }
        // 从校验结果中获取服务端证书
        let serverCertificatesData = Set(trust.af.certificateData)
        // 获取自定义证书
        let pinnedCertificatesData = Set(certificates.af.data)
        // 服务端证书与自定义证书是否匹配(通过判断两个集合存在交集确定)
        let pinnedCertificatesInServerData = !serverCertificatesData.isDisjoint(with: pinnedCertificatesData)
        if !pinnedCertificatesInServerData {
            // 不匹配则认为校验失败, 抛出错误
            throw AFError.serverTrustEvaluationFailed(reason: .certificatePinningFailed(host: host,
                                                                                        trust: trust,
                                                                                        pinnedCertificates: certificates,
                                                                                        serverCertificates: trust.af.certificates))
        }
    }
}

#if swift(>=5.5)
extension ServerTrustEvaluating where Self == PinnedCertificatesTrustEvaluator {
    /// Provides a default `PinnedCertificatesTrustEvaluator` instance.
    public static var pinnedCertificates: PinnedCertificatesTrustEvaluator { PinnedCertificatesTrustEvaluator() }

    /// Creates a `PinnedCertificatesTrustEvaluator` using the provided parameters.
    ///
    /// - Parameters:
    ///   - certificates:                 The certificates to use to evaluate the trust. All `cer`, `crt`, and `der`
    ///                                   certificates in `Bundle.main` by default.
    ///   - acceptSelfSignedCertificates: Adds the provided certificates as anchors for the trust evaluation, allowing
    ///                                   self-signed certificates to pass. `false` by default. THIS SETTING SHOULD BE
    ///                                   FALSE IN PRODUCTION!
    ///   - performDefaultValidation:     Determines whether default validation should be performed in addition to
    ///                                   evaluating the pinned certificates. `true` by default.
    ///   - validateHost:                 Determines whether or not the evaluator should validate the host, in addition
    ///                                   to performing the default evaluation, even if `performDefaultValidation` is
    ///                                   `false`. `true` by default.
    public static func pinnedCertificates(certificates: [SecCertificate] = Bundle.main.af.certificates,
                                          acceptSelfSignedCertificates: Bool = false,
                                          performDefaultValidation: Bool = true,
                                          validateHost: Bool = true) -> PinnedCertificatesTrustEvaluator {
        PinnedCertificatesTrustEvaluator(certificates: certificates,
                                         acceptSelfSignedCertificates: acceptSelfSignedCertificates,
                                         performDefaultValidation: performDefaultValidation,
                                         validateHost: validateHost)
    }
}
#endif

/// Uses the pinned public keys to validate the server trust. The server trust is considered valid if one of the pinned
/// public keys match one of the server certificate public keys. By validating both the certificate chain and host,
/// public key pinning provides a very secure form of server trust validation mitigating most, if not all, MITM attacks.
/// Applications are encouraged to always validate the host and require a valid certificate chain in production
/// environments.
/// 公钥校验器:  使用自定义公钥来校验服务端证书，需要注意的是因为没有把自定义证书加入到SecTrust的锚定证书中，所以如果用这个校验器来对自签名证书进行校验，会失败。因此如果要校验自签名证书，请用上面的自定义证书校验器
public final class PublicKeysTrustEvaluator: ServerTrustEvaluating {
    // 自定义公钥数组, 默认为app 所有内置证书中可用的公钥
    private let keys: [SecKey]
    // 是否执行默认校验, 默认true
    private let performDefaultValidation: Bool
    // 是否验证主机名, 默认true
    private let validateHost: Bool

    /// Creates a `PublicKeysTrustEvaluator` from the provided parameters.
    ///
    /// - Note: Default and host validation will fail when using this evaluator with self-signed certificates. Use
    ///         `PinnedCertificatesTrustEvaluator` if you need to use self-signed certificates.
    ///
    /// - Parameters:
    ///   - keys:                     The `SecKey`s to use to validate public keys. Defaults to the public keys of all
    ///                               certificates included in the main bundle.
    ///   - performDefaultValidation: Determines whether default validation should be performed in addition to
    ///                               evaluating the pinned certificates. `true` by default.
    ///   - validateHost:             Determines whether or not the evaluator should validate the host, in addition to
    ///                               performing the default evaluation, even if `performDefaultValidation` is `false`.
    ///                               `true` by default.
    public init(keys: [SecKey] = Bundle.main.af.publicKeys,
                performDefaultValidation: Bool = true,
                validateHost: Bool = true) {
        self.keys = keys
        self.performDefaultValidation = performDefaultValidation
        self.validateHost = validateHost
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        guard !keys.isEmpty else {
            throw AFError.serverTrustEvaluationFailed(reason: .noPublicKeysFound)
        }
        // 执行默认校验
        if performDefaultValidation {
            try trust.af.performDefaultValidation(forHost: host)
        }

        if validateHost {
            // 验证主机名
            try trust.af.performValidation(forHost: host)
        }
        // 默认校验成功后, 检测下自定义公钥有没有在服务端证书的公钥中存在
        let pinnedKeysInServerKeys: Bool = {
            // 挨个遍历自定义公钥数组与服务端证书的公钥数组, 存在相同对则校验成功
            for serverPublicKey in trust.af.publicKeys {
                for pinnedPublicKey in keys {
                    if serverPublicKey == pinnedPublicKey {
                        return true
                    }
                }
            }
            return false
        }()

        if !pinnedKeysInServerKeys {
            // 公钥匹配失败, 抛出错误
            throw AFError.serverTrustEvaluationFailed(reason: .publicKeyPinningFailed(host: host,
                                                                                      trust: trust,
                                                                                      pinnedKeys: keys,
                                                                                      serverKeys: trust.af.publicKeys))
        }
    }
}

#if swift(>=5.5)
extension ServerTrustEvaluating where Self == PublicKeysTrustEvaluator {
    /// Provides a default `PublicKeysTrustEvaluator` instance.
    public static var publicKeys: PublicKeysTrustEvaluator { PublicKeysTrustEvaluator() }

    /// Creates a `PublicKeysTrustEvaluator` from the provided parameters.
    ///
    /// - Note: Default and host validation will fail when using this evaluator with self-signed certificates. Use
    ///         `PinnedCertificatesTrustEvaluator` if you need to use self-signed certificates.
    ///
    /// - Parameters:
    ///   - keys:                     The `SecKey`s to use to validate public keys. Defaults to the public keys of all
    ///                               certificates included in the main bundle.
    ///   - performDefaultValidation: Determines whether default validation should be performed in addition to
    ///                               evaluating the pinned certificates. `true` by default.
    ///   - validateHost:             Determines whether or not the evaluator should validate the host, in addition to
    ///                               performing the default evaluation, even if `performDefaultValidation` is `false`.
    ///                               `true` by default.
    public static func publicKeys(keys: [SecKey] = Bundle.main.af.publicKeys,
                                  performDefaultValidation: Bool = true,
                                  validateHost: Bool = true) -> PublicKeysTrustEvaluator {
        PublicKeysTrustEvaluator(keys: keys, performDefaultValidation: performDefaultValidation, validateHost: validateHost)
    }
}
#endif

/// Uses the provided evaluators to validate the server trust. The trust is only considered valid if all of the
/// evaluators consider it valid.
public final class CompositeTrustEvaluator: ServerTrustEvaluating {
    private let evaluators: [ServerTrustEvaluating]

    /// Creates a `CompositeTrustEvaluator` from the provided evaluators.
    ///
    /// - Parameter evaluators: The `ServerTrustEvaluating` values used to evaluate the server trust.
    public init(evaluators: [ServerTrustEvaluating]) {
        self.evaluators = evaluators
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        try evaluators.evaluate(trust, forHost: host)
    }
}

#if swift(>=5.5)
extension ServerTrustEvaluating where Self == CompositeTrustEvaluator {
    /// Creates a `CompositeTrustEvaluator` from the provided evaluators.
    ///
    /// - Parameter evaluators: The `ServerTrustEvaluating` values used to evaluate the server trust.
    public static func composite(evaluators: [ServerTrustEvaluating]) -> CompositeTrustEvaluator {
        CompositeTrustEvaluator(evaluators: evaluators)
    }
}
#endif

/// Disables all evaluation which in turn will always consider any server trust as valid.
///
/// - Note: Instead of disabling server trust evaluation, it's a better idea to configure systems to properly trust test
///         certificates, as outlined in [this Apple tech note](https://developer.apple.com/library/archive/qa/qa1948/_index.html).
///
/// **THIS EVALUATOR SHOULD NEVER BE USED IN PRODUCTION!**
@available(*, deprecated, renamed: "DisabledTrustEvaluator", message: "DisabledEvaluator has been renamed DisabledTrustEvaluator.")
public typealias DisabledEvaluator = DisabledTrustEvaluator

/// Disables all evaluation which in turn will always consider any server trust as valid.
///
///
/// - Note: Instead of disabling server trust evaluation, it's a better idea to configure systems to properly trust test
///         certificates, as outlined in [this Apple tech note](https://developer.apple.com/library/archive/qa/qa1948/_index.html).
///
/// **THIS EVALUATOR SHOULD NEVER BE USED IN PRODUCTION!**
public final class DisabledTrustEvaluator: ServerTrustEvaluating {
    /// Creates an instance.
    public init() {}

    public func evaluate(_ trust: SecTrust, forHost host: String) throws {}
}

// MARK: - Extensions

extension Array where Element == ServerTrustEvaluating {
    #if os(Linux) || os(Windows)
    // Add this same convenience method for Linux/Windows.
    #else
    /// Evaluates the given `SecTrust` value for the given `host`.
    ///
    /// - Parameters:
    ///   - trust: The `SecTrust` value to evaluate.
    ///   - host:  The host for which to evaluate the `SecTrust` value.
    ///
    /// - Returns: Whether or not the evaluator considers the `SecTrust` value valid for `host`.
    /// 对需要认证的host 遍历数组来认证, 任何一个处理器失败都会抛出错误
    public func evaluate(_ trust: SecTrust, forHost host: String) throws {
        for evaluator in self {
            try evaluator.evaluate(trust, forHost: host)
        }
    }
    #endif
}

// Bundle扩展, 用来把app内置的全部证书, 公钥给取出来
extension Bundle: AlamofireExtended {}
extension AlamofireExtension where ExtendedType: Bundle {
    /// Returns all valid `cer`, `crt`, and `der` certificates in the bundle.
    /// 把bundle 中所有有效的证书都读取出来返回
    public var certificates: [SecCertificate] {
        paths(forResourcesOfTypes: [".cer", ".CER", ".crt", ".CRT", ".der", ".DER"]).compactMap { path in
            // 这里用compactMap 来把获取失败的证书过滤掉
            guard
                let certificateData = try? Data(contentsOf: URL(fileURLWithPath: path)) as CFData,
                let certificate = SecCertificateCreateWithData(nil, certificateData) else { return nil }

            return certificate
        }
    }

    /// Returns all public keys for the valid certificates in the bundle.
    /// 返回bundle 中所有可用证书的公钥
    public var publicKeys: [SecKey] {
        certificates.af.publicKeys
    }

    /// Returns all pathnames for the resources identified by the provided file extensions.
    ///
    /// - Parameter types: The filename extensions locate.
    ///
    /// - Returns:         All pathnames for the given filename extensions.
    /// 根据扩展类型数组, 把bundle 中所有这些扩展的文件路径以数组形式返回
    public func paths(forResourcesOfTypes types: [String]) -> [String] {
        Array(Set(types.flatMap { type.paths(forResourcesOfType: $0, inDirectory: nil) }))
    }
}
// iOS12 以上与以下的两套校验方法
extension SecTrust: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecTrust {
    /// Evaluates `self` after applying the `SecPolicy` value provided.
    ///
    /// - Parameter policy: The `SecPolicy` to apply to `self` before evaluation.
    ///
    /// - Throws:           Any `Error` from applying the `SecPolicy` or from evaluation.
    @available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, *)
    public func evaluate(afterApplying policy: SecPolicy) throws {
        try apply(policy: policy).af.evaluate()
    }

    /// Attempts to validate `self` using the `SecPolicy` provided and transforming any error produced using the closure passed.
    ///
    /// - Parameters:
    ///   - policy:        The `SecPolicy` used to evaluate `self`.
    ///   - errorProducer: The closure used transform the failed `OSStatus` and `SecTrustResultType`.
    /// - Throws:          Any `Error` from applying the `policy`, or the result of `errorProducer` if validation fails.
    @available(iOS, introduced: 10, deprecated: 12, renamed: "evaluate(afterApplying:)")
    @available(macOS, introduced: 10.12, deprecated: 10.14, renamed: "evaluate(afterApplying:)")
    @available(tvOS, introduced: 10, deprecated: 12, renamed: "evaluate(afterApplying:)")
    @available(watchOS, introduced: 3, deprecated: 5, renamed: "evaluate(afterApplying:)")
    public func validate(policy: SecPolicy, errorProducer: (_ status: OSStatus, _ result: SecTrustResultType) -> Error) throws {
        try apply(policy: policy).af.validate(errorProducer: errorProducer)
    }

    /// Applies a `SecPolicy` to `self`, throwing if it fails.
    ///
    /// - Parameter policy: The `SecPolicy`.
    ///
    /// - Returns: `self`, with the policy applied.
    /// - Throws: An `AFError.serverTrustEvaluationFailed` instance with a `.policyApplicationFailed` reason.
    public func apply(policy: SecPolicy) throws -> SecTrust {
        let status = SecTrustSetPolicies(type, policy)

        guard status.af.isSuccess else {
            throw AFError.serverTrustEvaluationFailed(reason: .policyApplicationFailed(trust: type,
                                                                                       policy: policy,
                                                                                       status: status))
        }

        return type
    }

    /// Evaluate `self`, throwing an `Error` if evaluation fails.
    ///
    /// - Throws: `AFError.serverTrustEvaluationFailed` with reason `.trustValidationFailed` and associated error from
    ///           the underlying evaluation.
    @available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, *)
    public func evaluate() throws {
        var error: CFError?
        let evaluationSucceeded = SecTrustEvaluateWithError(type, &error)

        if !evaluationSucceeded {
            throw AFError.serverTrustEvaluationFailed(reason: .trustEvaluationFailed(error: error))
        }
    }

    /// Validate `self`, passing any failure values through `errorProducer`.
    ///
    /// - Parameter errorProducer: The closure used to transform the failed `OSStatus` and `SecTrustResultType` into an
    ///                            `Error`.
    /// - Throws:                  The `Error` produced by the `errorProducer` closure.
    @available(iOS, introduced: 10, deprecated: 12, renamed: "evaluate()")
    @available(macOS, introduced: 10.12, deprecated: 10.14, renamed: "evaluate()")
    @available(tvOS, introduced: 10, deprecated: 12, renamed: "evaluate()")
    @available(watchOS, introduced: 3, deprecated: 5, renamed: "evaluate()")
    public func validate(errorProducer: (_ status: OSStatus, _ result: SecTrustResultType) -> Error) throws {
        var result = SecTrustResultType.invalid
        let status = SecTrustEvaluate(type, &result)

        guard status.af.isSuccess && result.af.isSuccess else {
            throw errorProducer(status, result)
        }
    }

    /// Sets a custom certificate chain on `self`, allowing full validation of a self-signed certificate and its chain.
    ///
    /// - Parameter certificates: The `SecCertificate`s to add to the chain.
    /// - Throws:                 Any error produced when applying the new certificate chain.
    public func setAnchorCertificates(_ certificates: [SecCertificate]) throws {
        // Add additional anchor certificates.
        let status = SecTrustSetAnchorCertificates(type, certificates as CFArray)
        guard status.af.isSuccess else {
            throw AFError.serverTrustEvaluationFailed(reason: .settingAnchorCertificatesFailed(status: status,
                                                                                               certificates: certificates))
        }

        // Trust only the set anchor certs.
        let onlyStatus = SecTrustSetAnchorCertificatesOnly(type, true)
        guard onlyStatus.af.isSuccess else {
            throw AFError.serverTrustEvaluationFailed(reason: .settingAnchorCertificatesFailed(status: onlyStatus,
                                                                                               certificates: certificates))
        }
    }

    /// The public keys contained in `self`.
    public var publicKeys: [SecKey] {
        certificates.af.publicKeys
    }

    #if swift(>=5.5.1) // Xcode 13.1 / 2021 SDKs.
    /// The `SecCertificate`s contained in `self`.
    public var certificates: [SecCertificate] {
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            return (SecTrustCopyCertificateChain(type) as? [SecCertificate]) ?? []
        } else {
            return (0..<SecTrustGetCertificateCount(type)).compactMap { index in
                SecTrustGetCertificateAtIndex(type, index)
            }
        }
    }
    #else
    /// The `SecCertificate`s contained in `self`.
    public var certificates: [SecCertificate] {
        (0..<SecTrustGetCertificateCount(type)).compactMap { index in
            SecTrustGetCertificateAtIndex(type, index)
        }
    }
    #endif

    /// The `Data` values for all certificates contained in `self`.
    public var certificateData: [Data] {
        certificates.af.data
    }

    /// Validates `self` after applying `SecPolicy.af.default`. This evaluation does not validate the hostname.
    ///
    /// - Parameter host: The hostname, used only in the error output if validation fails.
    /// - Throws: An `AFError.serverTrustEvaluationFailed` instance with a `.defaultEvaluationFailed` reason.
    public func performDefaultValidation(forHost host: String) throws {
        if #available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, *) {
            try evaluate(afterApplying: SecPolicy.af.default)
        } else {
            try validate(policy: SecPolicy.af.default) { status, result in
                AFError.serverTrustEvaluationFailed(reason: .defaultEvaluationFailed(output: .init(host, type, status, result)))
            }
        }
    }

    /// Validates `self` after applying `SecPolicy.af.hostname(host)`, which performs the default validation as well as
    /// hostname validation.
    ///
    /// - Parameter host: The hostname to use in the validation.
    /// - Throws:         An `AFError.serverTrustEvaluationFailed` instance with a `.defaultEvaluationFailed` reason.
    public func performValidation(forHost host: String) throws {
        if #available(iOS 12, macOS 10.14, tvOS 12, watchOS 5, *) {
            try evaluate(afterApplying: SecPolicy.af.hostname(host))
        } else {
            try validate(policy: SecPolicy.af.hostname(host)) { status, result in
                AFError.serverTrustEvaluationFailed(reason: .hostValidationFailed(output: .init(host, type, status, result)))
            }
        }
    }
}
// 三种安全策略, 用来校验服务端证书
extension SecPolicy: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecPolicy {
    /// Creates a `SecPolicy` instance which will validate server certificates but not require a host name match.
    /// 校验服务端证书, 但是不需要主机名匹配
    public static let `default` = SecPolicyCreateSSL(true, nil)

    /// Creates a `SecPolicy` instance which will validate server certificates and much match the provided hostname.
    ///
    /// - Parameter hostname: The hostname to validate against.
    ///
    /// - Returns:            The `SecPolicy`.
    /// 校验服务端证书, 同时必须匹配主机名
    public static func hostname(_ hostname: String) -> SecPolicy {
        SecPolicyCreateSSL(true, hostname as CFString)
    }

    /// Creates a `SecPolicy` which checks the revocation of certificates.
    ///
    /// - Parameter options: The `RevocationTrustEvaluator.Options` for evaluation.
    ///
    /// - Returns:           The `SecPolicy`.
    /// - Throws:            An `AFError.serverTrustEvaluationFailed` error with reason `.revocationPolicyCreationFailed`
    ///                      if the policy cannot be created.
    /// 校验证书是否被撤销, 创建策略失败会抛出异常
    public static func revocation(options: RevocationTrustEvaluator.Options) throws -> SecPolicy {
        guard let policy = SecPolicyCreateRevocation(options.rawValue) else {
            throw AFError.serverTrustEvaluationFailed(reason: .revocationPolicyCreationFailed)
        }

        return policy
    }
}
// 证书数组扩展, 提取全部的公钥
extension Array: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == [SecCertificate] {
    /// All `Data` values for the contained `SecCertificate`s.
    /// 把数组中的证书对象全部以Data 格式返回
    public var data: [Data] {
        type.map { SecCertificateCopyData($0) as Data }
    }

    /// All public `SecKey` values for the contained `SecCertificate`s.
    /// 把所有证书对象的公钥提取出来, 使用compactMap 过滤提取失败的对象
    public var publicKeys: [SecKey] {
        type.compactMap(\.af.publicKey)
    }
}
// 从证书中提取公钥, 如果提取失败, 返回nil
extension SecCertificate: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecCertificate {
    /// The public key for `self`, if it can be extracted.
    ///
    /// - Note: On 2020 OSes and newer, only RSA and ECDSA keys are supported.
    ///
    public var publicKey: SecKey? {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let trustCreationStatus = SecTrustCreateWithCertificates(type, policy, &trust)

        guard let createdTrust = trust, trustCreationStatus == errSecSuccess else { return nil }

        if #available(iOS 14, macOS 11, tvOS 14, watchOS 7, *) {
            return SecTrustCopyKey(createdTrust)
        } else {
            return SecTrustCopyPublicKey(createdTrust)
        }
    }
}

extension OSStatus: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == OSStatus {
    /// Returns whether `self` is `errSecSuccess`.
    public var isSuccess: Bool { type == errSecSuccess }
}

extension SecTrustResultType: AlamofireExtended {}
extension AlamofireExtension where ExtendedType == SecTrustResultType {
    /// Returns whether `self is `.unspecified` or `.proceed`.
    public var isSuccess: Bool {
        type == .unspecified || type == .proceed
    }
}
#endif
