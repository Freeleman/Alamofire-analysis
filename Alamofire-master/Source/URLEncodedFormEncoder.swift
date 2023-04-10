//
//  URLEncodedFormEncoder.swift
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

/// An object that encodes instances into URL-encoded query strings.
///
/// There is no published specification for how to encode collection types. By default, the convention of appending
/// `[]` to the key for array values (`foo[]=1&foo[]=2`), and appending the key surrounded by square brackets for
/// nested dictionary values (`foo[bar]=baz`) is used. Optionally, `ArrayEncoding` can be used to omit the
/// square brackets appended to array keys.
///
/// `BoolEncoding` can be used to configure how `Bool` values are encoded. The default behavior is to encode
/// `true` as 1 and `false` as 0.
///
/// `DateEncoding` can be used to configure how `Date` values are encoded. By default, the `.deferredToDate`
/// strategy is used, which formats dates from their structure.
///
/// `SpaceEncoding` can be used to configure how spaces are encoded. Modern encodings use percent replacement (`%20`),
/// while older encodings may expect spaces to be replaced with `+`.
///
/// This type is largely based on Vapor's [`url-encoded-form`](https://github.com/vapor/url-encoded-form) project.
public final class URLEncodedFormEncoder {
    /// Encoding to use for `Array` values.
    /// 数组编码方式
    public enum ArrayEncoding {
        /// An empty set of square brackets ("[]") are appended to the key for every value. This is the default encoding.
        case brackets
        /// No brackets are appended to the key and the key is encoded as is.
        case noBrackets
        /// Brackets containing the item index are appended. This matches the jQuery and Node.js behavior.
        case indexInBrackets

        /// Encodes the key according to the encoding.
        ///
        /// - Parameters:
        ///     - key:      The `key` to encode.
        ///     - index:   When this enum instance is `.indexInBrackets`, the `index` to encode.
        ///
        /// - Returns:          The encoded key.
        func encode(_ key: String, atIndex index: Int) -> String {
            switch self {
            case .brackets: return "\(key)[]"
            case .noBrackets: return key
            case .indexInBrackets: return "\(key)[\(index)]"
            }
        }
    }

    /// Encoding to use for `Bool` values.
    /// bool 编码方式
    public enum BoolEncoding {
        /// Encodes `true` as `1`, `false` as `0`.
        case numeric
        /// Encodes `true` as "true", `false` as "false". This is the default encoding.
        case literal

        /// Encodes the given `Bool` as a `String`.
        ///
        /// - Parameter value: The `Bool` to encode.
        ///
        /// - Returns:         The encoded `String`.
        func encode(_ value: Bool) -> String {
            switch self {
            case .numeric: return value ? "1" : "0"
            case .literal: return value ? "true" : "false"
            }
        }
    }

    /// Encoding to use for `Data` values.
    /// data 编码方式
    public enum DataEncoding {
        /// Defers encoding to the `Data` type.
        /// 延迟编码成Data, 若对Data的编码方式是deferredToData 类型, 会创建一个子编码器对Data进行编码, 会使用Data默认的编码格式(UInt8数组)
        case deferredToData
        /// Encodes `Data` as a Base64-encoded string. This is the default encoding.
        /// base64 编码
        case base64
        /// Encode the `Data` as a custom value encoded by the given closure.
        /// 使用闭包来编码成自定义格式的字符串
        case custom((Data) throws -> String)

        /// Encodes `Data` according to the encoding.
        ///
        /// - Parameter data: The `Data` to encode.
        ///
        /// - Returns:        The encoded `String`, or `nil` if the `Data` should be encoded according to its
        ///                   `Encodable` implementation.
        /// 编码data
        func encode(_ data: Data) throws -> String? {
            switch self {
            case .deferredToData: return nil
            case .base64: return data.base64EncodedString()
            case let .custom(encoding): return try encoding(data)
            }
        }
    }

    /// Encoding to use for `Date` values.
    /// 类似data 编码方式, 距离1970.1.1 的秒.毫秒
    public enum DateEncoding {
        /// ISO8601 and RFC3339 formatter.
        /// 把data 转换成ISO8601 字符串的Formatter
        private static let iso8601Formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = .withInternetDateTime
            return formatter
        }()

        /// Defers encoding to the `Date` type. This is the default encoding.
        /// 延迟编码date
        case deferredToDate
        /// Encodes `Date`s as seconds since midnight UTC on January 1, 1970.
        /// 编码成从1970.1.1 开始字符串
        case secondsSince1970
        /// Encodes `Date`s as milliseconds since midnight UTC on January 1, 1970.
        /// 编码成从1970.1.1 开始的毫秒字符串
        case millisecondsSince1970
        /// Encodes `Date`s according to the ISO8601 and RFC3339 standards.
        /// 编码成iso8601 标准字符串
        case iso8601
        /// Encodes `Date`s using the given `DateFormatter`.
        /// 使用自定义格式
        case formatted(DateFormatter)
        /// Encodes `Date`s using the given closure.
        /// 闭包自定义编码date
        case custom((Date) throws -> String)

        /// Encodes the date according to the encoding.
        ///
        /// - Parameter date: The `Date` to encode.
        ///
        /// - Returns:        The encoded `String`, or `nil` if the `Date` should be encoded according to its
        ///                   `Encodable` implementation.
        func encode(_ date: Date) throws -> String? {
            switch self {
            case .deferredToDate:
                return nil
            case .secondsSince1970:
                return String(date.timeIntervalSince1970)
            case .millisecondsSince1970:
                return String(date.timeIntervalSince1970 * 1000.0)
            case .iso8601:
                return DateEncoding.iso8601Formatter.string(from: date)
            case let .formatted(formatter):
                return formatter.string(from: date)
            case let .custom(closure):
                return try closure(date)
            }
        }
    }

    /// Encoding to use for keys.
    ///
    /// This type is derived from [`JSONEncoder`'s `KeyEncodingStrategy`](https://github.com/apple/swift/blob/6aa313b8dd5f05135f7f878eccc1db6f9fbe34ff/stdlib/public/Darwin/Foundation/JSONEncoder.swift#L128)
    /// and [`XMLEncoder`s `KeyEncodingStrategy`](https://github.com/MaxDesiatov/XMLCoder/blob/master/Sources/XMLCoder/Encoder/XMLEncoder.swift#L102).
    public enum KeyEncoding {
        /// Use the keys specified by each type. This is the default encoding.
        /// 默认格式
        case useDefaultKeys
        /// Convert from "camelCaseKeys" to "snake_case_keys" before writing a key.
        ///
        /// Capital characters are determined by testing membership in
        /// `CharacterSet.uppercaseLetters` and `CharacterSet.lowercaseLetters`
        /// (Unicode General Categories Lu and Lt).
        /// The conversion to lower case uses `Locale.system`, also known as
        /// the ICU "root" locale. This means the result is consistent
        /// regardless of the current user's locale and language preferences.
        ///
        /// Converting from camel case to snake case:
        /// 1. Splits words at the boundary of lower-case to upper-case
        /// 2. Inserts `_` between words
        /// 3. Lowercases the entire string
        /// 4. Preserves starting and ending `_`.
        ///
        /// For example, `oneTwoThree` becomes `one_two_three`. `_oneTwoThree_` becomes `_one_two_three_`.
        ///
        /// - Note: Using a key encoding strategy has a nominal performance cost, as each string key has to be converted.
        /// 驼峰转下划线蛇形, oneTwoThree -> one_two_three
        case convertToSnakeCase
        /// Same as convertToSnakeCase, but using `-` instead of `_`.
        /// For example `oneTwoThree` becomes `one-two-three`.
        /// 驼峰转串oneTwoThree -> one-two-three
        case convertToKebabCase
        /// Capitalize the first letter only.
        /// For example `oneTwoThree` becomes  `OneTwoThree`.
        /// 首字母大写 OneTwoThree
        case capitalized
        /// Uppercase all letters.
        /// For example `oneTwoThree` becomes  `ONETWOTHREE`.
        /// 全部大写
        case uppercased
        /// Lowercase all letters.
        /// For example `oneTwoThree` becomes  `onetwothree`.
        /// 小写
        case lowercased
        /// A custom encoding using the provided closure.
        /// 自定义编码规则
        case custom((String) -> String)

        func encode(_ key: String) -> String {
            switch self {
            case .useDefaultKeys: return key
            case .convertToSnakeCase: return convertToSnakeCase(key)
            case .convertToKebabCase: return convertToKebabCase(key)
            case .capitalized: return String(key.prefix(1).uppercased() + key.dropFirst())
            case .uppercased: return key.uppercased()
            case .lowercased: return key.lowercased()
            case let .custom(encoding): return encoding(key)
            }
        }
        // 蛇形
        private func convertToSnakeCase(_ key: String) -> String {
            convert(key, usingSeparator: "_")
        }
        // 串行
        private func convertToKebabCase(_ key: String) -> String {
            convert(key, usingSeparator: "-")
        }
        
        private func convert(_ key: String, usingSeparator separator: String) -> String {
            guard !key.isEmpty else { return key }
            // 存放分割字符串的range
            var words: [Range<String.Index>] = []
            // The general idea of this algorithm is to split words on
            // transition from lower to upper case, then on transition of >1
            // upper case characters to lowercase
            //
            // myProperty -> my_property
            // myURLProperty -> my_url_property
            //
            // It is assumed, per Swift naming conventions, that the first character of the key is lowercase.
            // 开始查找的index
            var wordStart = key.startIndex
            // 查找字符串的range
            var searchRange = key.index(after: wordStart)..<key.endIndex

            // Find next uppercase character
            // 开始编码查找
            while let upperCaseRange = key.rangeOfCharacter(from: CharacterSet.uppercaseLetters, options: [], range: searchRange) {
                // 大写字母前的range 第一个小写字符串
                let untilUpperCase = wordStart..<upperCaseRange.lowerBound
                // 加入words
                words.append(untilUpperCase)

                // Find next lowercase character
                // 从大写字符串后找小写字符串的range
                searchRange = upperCaseRange.lowerBound..<searchRange.upperBound
                guard let lowerCaseRange = key.rangeOfCharacter(from: CharacterSet.lowercaseLetters, options: [], range: searchRange) else {
                    // There are no more lower case letters. Just end here.
                    // 若没有小写字符串, 跳出循环
                    wordStart = searchRange.lowerBound
                    break
                }

                // Is the next lowercase letter more than 1 after the uppercase?
                // If so, we encountered a group of uppercase letters that we
                // should treat as its own word
                // 如果大写字符串长度大于1, 就把大写字符串认为是一个word
                // 大写字符串range 的startIndex 的后一位
                let nextCharacterAfterCapital = key.index(after: upperCaseRange.lowerBound)
                if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
                    // The next character after capital is a lower case character and therefore not a word boundary.
                    // Continue searching for the next upper case for the boundary.
                    // 是否与小写字符串的startIndex 相等, 相等就表示大写字符串只有一个字符串, 就把这个字符串跟后面的小写字符串一起当做一个word
                    wordStart = upperCaseRange.lowerBound
                } else {
                    // There was a range of >1 capital letters. Turn those into a word, stopping at the capital before the lower case character.
                    // 否则把大写字符串开始到小写字符串的startIndex 的前一位当做一个word
                    // URLProperty, 大写为URLP, URL 是一个word, Property 是一个word
                    let beforeLowerIndex = key.index(before: lowerCaseRange.lowerBound)
                    // 加入words
                    words.append(upperCaseRange.lowerBound..<beforeLowerIndex)

                    // Next word starts at the capital before the lowercase we just found
                    // 设置wordStart, 下次查找到字符串后取word 用
                    wordStart = beforeLowerIndex
                }
                // 下次搜索从小写字符串range 的尾部直到搜索range 的尾部
                searchRange = lowerCaseRange.upperBound..<searchRange.upperBound
            }
            // 循环完成, 加入结尾range
            words.append(wordStart..<searchRange.upperBound)
            // 全部变为小写, 使用separator 连接
            let result = words.map { range in
                key[range].lowercased()
            }.joined(separator: separator)

            return result
        }
    }

    /// Encoding to use for spaces.
    /// 空格编码格式
    public enum SpaceEncoding {
        /// Encodes spaces according to normal percent escaping rules (%20).
        /// 转为 %20
        case percentEscaped
        /// Encodes spaces as `+`,
        /// 转为 +
        case plusReplaced

        /// Encodes the string according to the encoding.
        ///
        /// - Parameter string: The `String` to encode.
        ///
        /// - Returns:          The encoded `String`.
        func encode(_ string: String) -> String {
            switch self {
            case .percentEscaped: return string.replacingOccurrences(of: " ", with: "%20")
            case .plusReplaced: return string.replacingOccurrences(of: " ", with: "+")
            }
        }
    }

    /// `URLEncodedFormEncoder` error.
    /// 编码错误时的错误定义
    public enum Error: Swift.Error {
        /// An invalid root object was created by the encoder. Only keyed values are valid.
        /// root 节点必须为key-value 数据
        case invalidRootObject(String)

        var localizedDescription: String {
            switch self {
            case let .invalidRootObject(object):
                return "URLEncodedFormEncoder requires keyed root object. Received \(object) instead."
            }
        }
    }

    /// Whether or not to sort the encoded key value pairs.
    ///
    /// - Note: This setting ensures a consistent ordering for all encodings of the same parameters. When set to `false`,
    ///         encoded `Dictionary` values may have a different encoded order each time they're encoded due to
    ///       ` Dictionary`'s random storage order, but `Encodable` types will maintain their encoded order.
    /// 常量属性与初始化
    /// 编码后的键值对是否根据key 排序, 默认true, 相同的params 编码出来的字典数据是相同的, 如果设置了false, 因为字典无序, 会导致相同params 编码出来的字典顺序不同
    public let alphabetizeKeyValuePairs: Bool
    /// The `ArrayEncoding` to use.
    public let arrayEncoding: ArrayEncoding
    /// The `BoolEncoding` to use.
    public let boolEncoding: BoolEncoding
    /// THe `DataEncoding` to use.
    public let dataEncoding: DataEncoding
    /// The `DateEncoding` to use.
    public let dateEncoding: DateEncoding
    /// The `KeyEncoding` to use.
    public let keyEncoding: KeyEncoding
    /// The `SpaceEncoding` to use.
    public let spaceEncoding: SpaceEncoding
    /// The `CharacterSet` of allowed (non-escaped) characters.
    public var allowedCharacters: CharacterSet

    /// Creates an instance from the supplied parameters.
    ///
    /// - Parameters:
    ///   - alphabetizeKeyValuePairs: Whether or not to sort the encoded key value pairs. `true` by default.
    ///   - arrayEncoding:            The `ArrayEncoding` to use. `.brackets` by default.
    ///   - boolEncoding:             The `BoolEncoding` to use. `.numeric` by default.
    ///   - dataEncoding:             The `DataEncoding` to use. `.base64` by default.
    ///   - dateEncoding:             The `DateEncoding` to use. `.deferredToDate` by default.
    ///   - keyEncoding:              The `KeyEncoding` to use. `.useDefaultKeys` by default.
    ///   - spaceEncoding:            The `SpaceEncoding` to use. `.percentEscaped` by default.
    ///   - allowedCharacters:        The `CharacterSet` of allowed (non-escaped) characters. `.afURLQueryAllowed` by
    ///                               default.
    /// 初始化, 全部属性都有默认值
    public init(alphabetizeKeyValuePairs: Bool = true,
                arrayEncoding: ArrayEncoding = .brackets,
                boolEncoding: BoolEncoding = .numeric,
                dataEncoding: DataEncoding = .base64,
                dateEncoding: DateEncoding = .deferredToDate,
                keyEncoding: KeyEncoding = .useDefaultKeys,
                spaceEncoding: SpaceEncoding = .percentEscaped,
                allowedCharacters: CharacterSet = .afURLQueryAllowed) {
        self.alphabetizeKeyValuePairs = alphabetizeKeyValuePairs
        self.arrayEncoding = arrayEncoding
        self.boolEncoding = boolEncoding
        self.dataEncoding = dataEncoding
        self.dateEncoding = dateEncoding
        self.keyEncoding = keyEncoding
        self.spaceEncoding = spaceEncoding
        self.allowedCharacters = allowedCharacters
    }
    /// 核心编码方法, 把value 编码成自定义的URLEncodedFormComponent 数据, 默认会编码成字典类型
    /// 另外两个编码方法都会先调用该方法, 在对数据进行处理
    func encode(_ value: Encodable) throws -> URLEncodedFormComponent {
        // 表单数据格式, 默认字典类型
        let context = URLEncodedFormContext(.object([]))
        // 编码器
        let encoder = _URLEncodedFormEncoder(context: context,
                                             boolEncoding: boolEncoding,
                                             dataEncoding: dataEncoding,
                                             dateEncoding: dateEncoding)
        try value.encode(to: encoder)

        return context.component
    }

    /// Encodes the `value` as a URL form encoded `String`.
    ///
    /// - Parameter value: The `Encodable` value.`
    ///
    /// - Returns:         The encoded `String`.
    /// - Throws:          An `Error` or `EncodingError` instance if encoding fails.
    public func encode(_ value: Encodable) throws -> String {
        // 先编码成 URLEncodedFormComponent
        let component: URLEncodedFormComponent = try encode(value)
        // 转成字典类型数据, 这里的object 的类型是一个包含key, value 元组
        // 不是直接的字典, 因为字典无序, 使用元组数组可以保证keyvalue 的顺序
        guard case let .object(object) = component else {
            throw Error.invalidRootObject("\(component)")
        }
        // 序列化
        let serializer = URLEncodedFormSerializer(alphabetizeKeyValuePairs: alphabetizeKeyValuePairs,
                                                  arrayEncoding: arrayEncoding,
                                                  keyEncoding: keyEncoding,
                                                  spaceEncoding: spaceEncoding,
                                                  allowedCharacters: allowedCharacters)
        // 序列化成query string
        let query = serializer.serialize(object)

        return query
    }

    /// Encodes the value as `Data`. This is performed by first creating an encoded `String` and then returning the
    /// `.utf8` data.
    ///
    /// - Parameter value: The `Encodable` value.
    ///
    /// - Returns:         The encoded `Data`.
    ///
    /// - Throws:          An `Error` or `EncodingError` instance if encoding fails.
    public func encode(_ value: Encodable) throws -> Data {
        let string: String = try encode(value)

        return Data(string.utf8)
    }
}
// 用来把数据编码成URLEncodedFormComponent 表单数据的编码器
final class _URLEncodedFormEncoder {
    // Encoder 协议属性, 用来编码key-value 数据
    var codingPath: [CodingKey]
    // Returns an empty dictionary, as this encoder doesn't support userInfo.
    // 不支持userInfo, 直接返回
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    // 上下文属性, 保存编码数据, 同时在递归编码数据时传递使用, 最终数据
    let context: URLEncodedFormContext
    // 三种特殊类型编码方式
    private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
    private let dataEncoding: URLEncodedFormEncoder.DataEncoding
    private let dateEncoding: URLEncodedFormEncoder.DateEncoding

    init(context: URLEncodedFormContext,
         codingPath: [CodingKey] = [],
         boolEncoding: URLEncodedFormEncoder.BoolEncoding,
         dataEncoding: URLEncodedFormEncoder.DataEncoding,
         dateEncoding: URLEncodedFormEncoder.DateEncoding) {
        self.context = context
        self.codingPath = codingPath
        self.boolEncoding = boolEncoding
        self.dataEncoding = dataEncoding
        self.dateEncoding = dateEncoding
    }
}
// 实现Encoder 协议, 用来编码数据
extension _URLEncodedFormEncoder: Encoder {
    // 保存key-value 数据容器
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        // 返回_URLEncodedFormEncoder.KeyedContainer, 数据会存在context 中
        let container = _URLEncodedFormEncoder.KeyedContainer<Key>(context: context,
                                                                   codingPath: codingPath,
                                                                   boolEncoding: boolEncoding,
                                                                   dataEncoding: dataEncoding,
                                                                   dateEncoding: dateEncoding)
        return KeyedEncodingContainer(container)
    }
    // 保存数组数据的容器
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        _URLEncodedFormEncoder.UnkeyedContainer(context: context,
                                                codingPath: codingPath,
                                                boolEncoding: boolEncoding,
                                                dataEncoding: dataEncoding,
                                                dateEncoding: dateEncoding)
    }
    // 保存单个值的容器
    func singleValueContainer() -> SingleValueEncodingContainer {
        _URLEncodedFormEncoder.SingleValueContainer(context: context,
                                                    codingPath: codingPath,
                                                    boolEncoding: boolEncoding,
                                                    dataEncoding: dataEncoding,
                                                    dateEncoding: dateEncoding)
    }
}
// 编码传递上下文, 编码完成返回的结果就是持有的属性
final class URLEncodedFormContext {
    var component: URLEncodedFormComponent

    init(_ component: URLEncodedFormComponent) {
        self.component = component
    }
}
// 保存编码的数据
enum URLEncodedFormComponent {
    // 对应key-value 数据对
    typealias Object = [(key: String, value: URLEncodedFormComponent)]

    case string(String)// 字符串
    case array([URLEncodedFormComponent]) // 数组
    case object(Object) // 有序字典

    /// Converts self to an `[URLEncodedFormData]` or returns `nil` if not convertible.
    /// 快速获取数组数据, 字符串与字典返回nil
    var array: [URLEncodedFormComponent]? {
        switch self {
        case let .array(array): return array
        default: return nil
        }
    }

    /// Converts self to an `Object` or returns `nil` if not convertible.
    /// 快速获取字典, 其他返回nil
    var object: Object? {
        switch self {
        case let .object(object): return object
        default: return nil
        }
    }

    /// Sets self to the supplied value at a given path.
    ///
    ///     data.set(to: "hello", at: ["path", "to", "value"])
    ///
    /// - parameters:
    ///     - value: Value of `Self` to set at the supplied path.
    ///     - path: `CodingKey` path to update with the supplied value.
    public mutating func set(to value: URLEncodedFormComponent, at path: [CodingKey]) {
        set(&self, to: value, at: path)
    }

    /// Recursive backing method to `set(to:at:)`.
    /// 递归设置key-value
    /// context, 递归当前节点, value 需要保存的值, path 保存的keypaths
    /// 第一次, context 为self, 随着递归, 根据path 顺序一层层传下去, context 往下查找创建, 直到完成整个树创建
    private func set(_ context: inout URLEncodedFormComponent, to value: URLEncodedFormComponent, at path: [CodingKey]) {
        guard !path.isEmpty else {
            // 如果path 为空, 直接把value 设置给当前节点, return
            context = value
            return
        }
        // 第一个path
        let end = path[0]
        // 子节点, 需要根据path 判断子节点类型
        var child: URLEncodedFormComponent
        switch path.count {
        case 1:
            // 只有一个, 保存child
            child = value
        case 2...:
            // 多个path, 递归
            if let index = end.intValue {
                // 第一个是int, 需要数组保存
                // 获取当前节点的array 类型
                let array = context.array ?? []
                if array.count > index {
                    // array 数据大于index, 表示更新, 取出需要更新的节点作为子节点
                    child = array[index]
                } else {
                    // 否则新增, 创建子节点
                    child = .array([])
                }
                // 递归调用
                set(&child, to: value, at: Array(path[1...]))
            } else {
                // 字典保存
                // 根据第一个path, 找到子节点, 找到就更新, 否则新增需要创建子节点
                child = context.object?.first { $0.key == end.stringValue }?.value ?? .object(.init())
                set(&child, to: value, at: Array(path[1...]))
            }
        default: fatalError("Unreachable")
        }
        // 递归完成后, 需要把子节点插入到当前节点context 中
        if let index = end.intValue {
            // 第一个path 数组
            if var array = context.array {
                // 如果当前节点为数组节点, 直接把child 插入或者更新到数组中
                if array.count > index {
                    // 更新
                    array[index] = child
                } else {
                    // 插入
                    array.append(child)
                }
                // 更新当前节点
                context = .array(array)
            } else {
                // 否则直接把当前阶段设置为数组节点
                context = .array([child])
            }
        } else {
            // 第一个path 为字典
            if var object = context.object {
                // 如果当前节点为字典, 把child 插入或者更新
                if let index = object.firstIndex(where: { $0.key == end.stringValue }) {
                    // 更新
                    object[index] = (key: end.stringValue, value: child)
                } else {
                    // 插入
                    object.append((key: end.stringValue, value: child))
                }
                // 更新当前节点
                context = .object(object)
            } else {
                // 否则把当前节点设置为字典节点
                context = .object([(key: end.stringValue, value: child)])
            }
        }
    }
}
// 保存字典的key, 和数组的index
struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init<Key>(_ base: Key) where Key: CodingKey {
        if let intValue = base.intValue {
            self.init(intValue: intValue)!
        } else {
            self.init(stringValue: base.stringValue)!
        }
    }
}
// 主要作用是用来编码字典数据, 本身类声明中只是保存一些属性与定义了一个追加keypath 的方法
extension _URLEncodedFormEncoder {
    final class KeyedContainer<Key> where Key: CodingKey {
        var codingPath: [CodingKey]

        private let context: URLEncodedFormContext
        private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
        private let dataEncoding: URLEncodedFormEncoder.DataEncoding
        private let dateEncoding: URLEncodedFormEncoder.DateEncoding

        init(context: URLEncodedFormContext,
             codingPath: [CodingKey],
             boolEncoding: URLEncodedFormEncoder.BoolEncoding,
             dataEncoding: URLEncodedFormEncoder.DataEncoding,
             dateEncoding: URLEncodedFormEncoder.DateEncoding) {
            self.context = context
            self.codingPath = codingPath
            self.boolEncoding = boolEncoding
            self.dataEncoding = dataEncoding
            self.dateEncoding = dateEncoding
        }
        // 嵌套追加key
        private func nestedCodingPath(for key: CodingKey) -> [CodingKey] {
            codingPath + [key]
        }
    }
}
// 追加keypath, 根据value 类型把编码方式分发
extension _URLEncodedFormEncoder.KeyedContainer: KeyedEncodingContainerProtocol {
    // 不支持nil
    func encodeNil(forKey key: Key) throws {
        let context = EncodingError.Context(codingPath: codingPath,
                                            debugDescription: "URLEncodedFormEncoder cannot encode nil values.")
        throw EncodingError.invalidValue("\(key): nil", context)
    }
    // 单个数据
    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        var container = nestedSingleValueEncoder(for: key)
        try container.encode(value)
    }
    // 嵌套单个数据编码容器
    func nestedSingleValueEncoder(for key: Key) -> SingleValueEncodingContainer {
        let container = _URLEncodedFormEncoder.SingleValueContainer(context: context,
                                                                    codingPath: nestedCodingPath(for: key),
                                                                    boolEncoding: boolEncoding,
                                                                    dataEncoding: dataEncoding,
                                                                    dateEncoding: dateEncoding)

        return container
    }
    // 嵌套数组编码容器
    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let container = _URLEncodedFormEncoder.UnkeyedContainer(context: context,
                                                                codingPath: nestedCodingPath(for: key),
                                                                boolEncoding: boolEncoding,
                                                                dataEncoding: dataEncoding,
                                                                dateEncoding: dateEncoding)

        return container
    }
    // key-value 编码容器
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let container = _URLEncodedFormEncoder.KeyedContainer<NestedKey>(context: context,
                                                                         codingPath: nestedCodingPath(for: key),
                                                                         boolEncoding: boolEncoding,
                                                                         dataEncoding: dataEncoding,
                                                                         dateEncoding: dateEncoding)

        return KeyedEncodingContainer(container)
    }
    // 父编码器
    func superEncoder() -> Encoder {
        _URLEncodedFormEncoder(context: context,
                               codingPath: codingPath,
                               boolEncoding: boolEncoding,
                               dataEncoding: dataEncoding,
                               dateEncoding: dateEncoding)
    }
    // 父编码器
    func superEncoder(forKey key: Key) -> Encoder {
        _URLEncodedFormEncoder(context: context,
                               codingPath: nestedCodingPath(for: key),
                               boolEncoding: boolEncoding,
                               dataEncoding: dataEncoding,
                               dateEncoding: dateEncoding)
    }
}

extension _URLEncodedFormEncoder {
    final class SingleValueContainer {
        var codingPath: [CodingKey]
        // 记录是否编码过
        private var canEncodeNewValue = true

        private let context: URLEncodedFormContext
        private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
        private let dataEncoding: URLEncodedFormEncoder.DataEncoding
        private let dateEncoding: URLEncodedFormEncoder.DateEncoding

        init(context: URLEncodedFormContext,
             codingPath: [CodingKey],
             boolEncoding: URLEncodedFormEncoder.BoolEncoding,
             dataEncoding: URLEncodedFormEncoder.DataEncoding,
             dateEncoding: URLEncodedFormEncoder.DateEncoding) {
            self.context = context
            self.codingPath = codingPath
            self.boolEncoding = boolEncoding
            self.dataEncoding = dataEncoding
            self.dateEncoding = dateEncoding
        }
        // 检测是否能编码新数据(编码一个值后canEncodeNewValue 就会被设置为false, 就不允许在编码新值了)
        private func checkCanEncode(value: Any?) throws {
            guard canEncodeNewValue else {
                let context = EncodingError.Context(codingPath: codingPath,
                                                    debugDescription: "Attempt to encode value through single value container when previously value already encoded.")
                throw EncodingError.invalidValue(value as Any, context)
            }
        }
    }
}

extension _URLEncodedFormEncoder.SingleValueContainer: SingleValueEncodingContainer {
    // 不支持nil
    func encodeNil() throws {
        try checkCanEncode(value: nil)
        defer { canEncodeNewValue = false }

        let context = EncodingError.Context(codingPath: codingPath,
                                            debugDescription: "URLEncodedFormEncoder cannot encode nil values.")
        throw EncodingError.invalidValue("nil", context)
    }

    func encode(_ value: Bool) throws {
        try encode(value, as: String(boolEncoding.encode(value)))
    }

    func encode(_ value: String) throws {
        try encode(value, as: value)
    }

    func encode(_ value: Double) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Float) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int8) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int16) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int32) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: Int64) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt8) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt16) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt32) throws {
        try encode(value, as: String(value))
    }

    func encode(_ value: UInt64) throws {
        try encode(value, as: String(value))
    }
    // 私有方法泛型编码数据
    private func encode<T>(_ value: T, as string: String) throws where T: Encodable {
        // 检测是否能编码
        try checkCanEncode(value: value)
        defer { canEncodeNewValue = false }
        // 把值使用string 存进context
        context.component.set(to: .string(string), at: codingPath)
    }
    // 编码非标准泛型数据
    // 这里对Date, Data, Decimal先进行了判断处理, 会先试图以原数据类型进行编码, 如果没有规定编码方法, 就使用_URLEncodedFormEncoder 对value 再次进行编码, 系统会使用value 的底层数据类型进行再次编码(Date会使用Double, Data会使用[UInt8]数组)
    func encode<T>(_ value: T) throws where T: Encodable {
        switch value {
        case let date as Date:
            // Date 判断下是否使用Date 默认类型进行延迟编码
            guard let string = try dateEncoding.encode(date) else {
                // 如果是用默认类型进行延迟编码, 就使用_URLEncodedFormEncoder 再次编码
                try attemptToEncode(value)
                return
            }
            // 否则使用string 编码
            try encode(value, as: string)
        case let data as Data:
            guard let string = try dataEncoding.encode(data) else {
                try attemptToEncode(value)
                return
            }

            try encode(value, as: string)
        case let decimal as Decimal:
            // Decimal's `Encodable` implementation returns an object, not a single value, so override it.
            try encode(value, as: String(describing: decimal))
        default:
            try attemptToEncode(value)
        }
    }

    private func attemptToEncode<T>(_ value: T) throws where T: Encodable {
        try checkCanEncode(value: value)
        defer { canEncodeNewValue = false }

        let encoder = _URLEncodedFormEncoder(context: context,
                                             codingPath: codingPath,
                                             boolEncoding: boolEncoding,
                                             dataEncoding: dataEncoding,
                                             dateEncoding: dateEncoding)
        try value.encode(to: encoder)
    }
}
// 编码数组数据
extension _URLEncodedFormEncoder {
    final class UnkeyedContainer {
        var codingPath: [CodingKey]

        var count = 0 // 记录数据index, 新增+1
        var nestedCodingPath: [CodingKey] {
            codingPath + [AnyCodingKey(intValue: count)!]
        }

        private let context: URLEncodedFormContext
        private let boolEncoding: URLEncodedFormEncoder.BoolEncoding
        private let dataEncoding: URLEncodedFormEncoder.DataEncoding
        private let dateEncoding: URLEncodedFormEncoder.DateEncoding

        init(context: URLEncodedFormContext,
             codingPath: [CodingKey],
             boolEncoding: URLEncodedFormEncoder.BoolEncoding,
             dataEncoding: URLEncodedFormEncoder.DataEncoding,
             dateEncoding: URLEncodedFormEncoder.DateEncoding) {
            self.context = context
            self.codingPath = codingPath
            self.boolEncoding = boolEncoding
            self.dataEncoding = dataEncoding
            self.dateEncoding = dateEncoding
        }
    }
}

extension _URLEncodedFormEncoder.UnkeyedContainer: UnkeyedEncodingContainer {
    // 不支持nil
    func encodeNil() throws {
        let context = EncodingError.Context(codingPath: codingPath,
                                            debugDescription: "URLEncodedFormEncoder cannot encode nil values.")
        throw EncodingError.invalidValue("nil", context)
    }
    // 编码单个值
    func encode<T>(_ value: T) throws where T: Encodable {
        var container = nestedSingleValueContainer()
        try container.encode(value)
    }
    // 单个编码容器
    func nestedSingleValueContainer() -> SingleValueEncodingContainer {
        // 编码完成, +1
        defer { count += 1 }

        return _URLEncodedFormEncoder.SingleValueContainer(context: context,
                                                           codingPath: nestedCodingPath,
                                                           boolEncoding: boolEncoding,
                                                           dataEncoding: dataEncoding,
                                                           dateEncoding: dateEncoding)
    }
    // key-value 编码容器
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        defer { count += 1 }
        let container = _URLEncodedFormEncoder.KeyedContainer<NestedKey>(context: context,
                                                                         codingPath: nestedCodingPath,
                                                                         boolEncoding: boolEncoding,
                                                                         dataEncoding: dataEncoding,
                                                                         dateEncoding: dateEncoding)

        return KeyedEncodingContainer(container)
    }
    // 数组编码容器
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        defer { count += 1 }

        return _URLEncodedFormEncoder.UnkeyedContainer(context: context,
                                                       codingPath: nestedCodingPath,
                                                       boolEncoding: boolEncoding,
                                                       dataEncoding: dataEncoding,
                                                       dateEncoding: dateEncoding)
    }
    // 父编码器
    func superEncoder() -> Encoder {
        defer { count += 1 }

        return _URLEncodedFormEncoder(context: context,
                                      codingPath: codingPath,
                                      boolEncoding: boolEncoding,
                                      dataEncoding: dataEncoding,
                                      dateEncoding: dateEncoding)
    }
}
// 序列化编码的结果数据
final class URLEncodedFormSerializer {
    private let alphabetizeKeyValuePairs: Bool
    private let arrayEncoding: URLEncodedFormEncoder.ArrayEncoding
    private let keyEncoding: URLEncodedFormEncoder.KeyEncoding
    private let spaceEncoding: URLEncodedFormEncoder.SpaceEncoding
    private let allowedCharacters: CharacterSet

    init(alphabetizeKeyValuePairs: Bool,
         arrayEncoding: URLEncodedFormEncoder.ArrayEncoding,
         keyEncoding: URLEncodedFormEncoder.KeyEncoding,
         spaceEncoding: URLEncodedFormEncoder.SpaceEncoding,
         allowedCharacters: CharacterSet) {
        self.alphabetizeKeyValuePairs = alphabetizeKeyValuePairs
        self.arrayEncoding = arrayEncoding
        self.keyEncoding = keyEncoding
        self.spaceEncoding = spaceEncoding
        self.allowedCharacters = allowedCharacters
    }
    // 解析跟字典对象
    func serialize(_ object: URLEncodedFormComponent.Object) -> String {
        var output: [String] = []
        for (key, component) in object {
            // 遍历字典, 把每队数据解析为string
            let value = serialize(component, forKey: key)
            output.append(value)
        }
        // 排序
        output = alphabetizeKeyValuePairs ? output.sorted() : output
        // 拼接
        return output.joinedWithAmpersands()
    }
    // 解析字典中对象, key=value
    func serialize(_ component: URLEncodedFormComponent, forKey key: String) -> String {
        switch component {
        case let .string(string): return "\(escape(keyEncoding.encode(key)))=\(escape(string))" // string 直接对key 编码, 拼接字符串
        case let .array(array): return serialize(array, forKey: key) // 数组字典用这两个解析方法
        case let .object(object): return serialize(object, forKey: key)
        }
    }
    // 字典中的字典对象, 格式key[subKey]=value
    func serialize(_ object: URLEncodedFormComponent.Object, forKey key: String) -> String {
        var segments: [String] = object.map { subKey, value in
            let keyPath = "[\(subKey)]"
            return serialize(value, forKey: key + keyPath)
        }
        segments = alphabetizeKeyValuePairs ? segments.sorted() : segments

        return segments.joinedWithAmpersands()
    }
    // 字典里的数组对象, key[]=value, 或者key=value
    func serialize(_ array: [URLEncodedFormComponent], forKey key: String) -> String {
        var segments: [String] = array.enumerated().map { index, component in
            let keyPath = arrayEncoding.encode(key, atIndex: index)
            return serialize(component, forKey: keyPath)
        }
        segments = alphabetizeKeyValuePairs ? segments.sorted() : segments

        return segments.joinedWithAmpersands()
    }
    // url 转义
    func escape(_ query: String) -> String {
        var allowedCharactersWithSpace = allowedCharacters
        allowedCharactersWithSpace.insert(charactersIn: " ")
        let escapedQuery = query.addingPercentEncoding(withAllowedCharacters: allowedCharactersWithSpace) ?? query
        let spaceEncodedQuery = spaceEncoding.encode(escapedQuery)

        return spaceEncodedQuery
    }
}
// 用& 拼接
extension Array where Element == String {
    func joinedWithAmpersands() -> String {
        joined(separator: "&")
    }
}
// 需要转义的字符
extension CharacterSet {
    /// Creates a CharacterSet from RFC 3986 allowed characters.
    ///
    /// RFC 3986 states that the following characters are "reserved" characters.
    ///
    /// - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
    /// - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
    ///
    /// In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
    /// query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
    /// should be percent-escaped in the query string.
    public static let afURLQueryAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        let encodableDelimiters = CharacterSet(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

        return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
    }()
}
