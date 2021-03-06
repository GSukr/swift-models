// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

public struct BytePairEncoder {
    public let vocabulary: Vocabulary
    public let mergePairs: [Pair: Int]
    public let reversedMergePairs: [String: Pair]
    public let useCache: Bool

    // TODO: Find a nice way to support caching.
    /// A cache used to store encoded tokens and thus speed up encoding.
    //  private var cache: [String: [String]]

    public init(vocabulary: Vocabulary, mergePairs: [Pair: Int], useCache: Bool = true) {
        self.vocabulary = vocabulary
        self.mergePairs = mergePairs
        self.reversedMergePairs = [String: Pair](uniqueKeysWithValues: mergePairs.map {
        ($0.key.left + $0.key.right, $0.key)
        })
        self.useCache = useCache
        // self.cache = [:]
    }

    /// Encodes the provided token to a sequence of BPE-coded tokens.
    ///
    /// - Parameters:
    ///   - token: Token to encode.
    /// - Returns: Array containing the BPE-coded tokens.
    public func encode(token: String) -> [String] {
        // if let cached = cache[token] { return cached }
        // let token = " " + token
        let encodedToken = String(String.UnicodeScalarView(token.utf8.map {
            BytePairEncoder.bytesToUnicode[$0]!
        }))
        var parts = BytePairEncoder.splitWithDelimiters(
            token: encodedToken,
            glossaryRegex: BytePairEncoder.defaultGlossaryRegex)
        if parts.count < 2 { return parts }
        var pairs = (0..<parts.count - 1).map { index in Pair(parts[index], parts[index + 1]) }
        while !pairs.isEmpty {
            let pair = pairs.min { mergePairs[$0] ?? Int.max < mergePairs[$1] ?? Int.max }!
            if !mergePairs.keys.contains(pair) { break }
            parts = BytePairEncoder.replacePair(pair: pair, tokenParts: parts)
            if parts.count < 2 { break }
            pairs = (0..<parts.count - 1).map { index in Pair(parts[index], parts[index + 1]) }
        }

        // Check if the new words parts are in the vocabulary, and backtrack if necessary.
        let encoded = parts.flatMap { part -> [String] in
        if vocabulary.contains(part) { return [part] }
            return splitRecursively(part)
        }

        // Update the cache and return.
        // if useCache { cache[token] = encoded }
        return encoded
    }
}

extension BytePairEncoder {
    public struct Pair: Hashable {
        public let left: String
        public let right: String

        public init(_ left: String, _ right: String) {
            self.left = left
            self.right = right
        }
    }

    internal static let defaultGlossary: [String] = [
        "e.g", "i.e", "&amp;", "&#124;", "&lt;", "&gt;", "&apos;", "&quot;", "&#91;", "&#93;"]

    internal static let defaultGlossaryRegex: NSRegularExpression = {
        let escapedGlossary = defaultGlossary.map { "\\Q\($0)\\E" }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?:\(escapedGlossary))|(?!\(escapedGlossary))")
    }()

    // TODO: Add documentation.
    internal static let bytesToUnicode: [UInt8: UnicodeScalar] = {
        var bytes = [UInt8](33...126) + [UInt8](161...172) + [UInt8](174...255)
        var characters = bytes.map(UInt32.init)
        var offset = UInt32(0)
        for byte in 0...UInt8(255) {
            if !bytes.contains(byte) {
                bytes.append(byte)
                characters.append(UInt32(offset + 256))
                offset += 1
            }
        }
        return [UInt8: UnicodeScalar](
            uniqueKeysWithValues: zip(bytes, characters.map { UnicodeScalar($0)! }))
    }()

    /// Recursively splits `token` into smaller units (by reversing BPE merges) until all units
    /// are either in the provided vocabulary, or cannot be split further.
    ///
    /// - Parameters:
    ///   - token: Token that needs to be split.
    internal func splitRecursively(_ token: String) -> [String] {
        guard let pair = reversedMergePairs[token] else { return [token] }
        let leftParts = vocabulary.contains(pair.left) ?
            [pair.left] :
            splitRecursively(pair.left)
        let rightParts = vocabulary.contains(pair.right) ?
            [pair.right] :
            splitRecursively(pair.right)
        return leftParts + rightParts
    }

    // TODO: Add documentation.
    internal static func splitWithDelimiters(
        token: String,
        glossaryRegex: NSRegularExpression,
        keepEmpty: Bool = false
    ) -> [String] {
        let matches = glossaryRegex.matches(
            in: token,
            range: NSRange(token.startIndex..., in: token))
        var parts = [String]()
        parts.reserveCapacity(token.count)
        var lastEnd = token.startIndex
        for match in matches {
            let start = token.index(token.startIndex, offsetBy: match.range.lowerBound)
            if lastEnd != start { parts.append(String(token[lastEnd..<start])) }
            lastEnd = token.index(token.startIndex, offsetBy: match.range.upperBound)
        }
        if lastEnd != token.endIndex {
            parts.append(String(token[lastEnd...]))
        }
        return parts
    }

    /// Replaces all occurrences of the provided symbol pair in `token` with the joined symbol.
    ///
    /// - Parameters:
    ///   - pair: Symbol pair to replace in `token`.
    ///   - token: Token as a sequence of symbols.
    /// - Returns: New token with the provided pair replaced for the joined symbol.
    internal static func replacePair(pair: Pair, tokenParts: [String]) -> [String] {
        var newTokenParts = [String]()
        newTokenParts.reserveCapacity(tokenParts.count)
        var j = 0
        while j < tokenParts.count - 1 {
            let part1 = tokenParts[j]
            let part2 = tokenParts[j + 1]
            if part1 == pair.left && part2 == pair.right {
                let joinedPair = part1 + part2
                newTokenParts.append(joinedPair)
                j += 2
            } else {
                newTokenParts.append(tokenParts[j])
                j += 1
            }
        }
        if j == tokenParts.count - 1 {
            newTokenParts.append(tokenParts[j])
        }
        return newTokenParts
    }
}
