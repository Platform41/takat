import Foundation

struct JSONLLines: Sequence {
    let data: Data

    func makeIterator() -> Iterator {
        Iterator(data: data)
    }

    struct Iterator: IteratorProtocol {
        let data: Data
        var start: Data.Index

        init(data: Data) {
            self.data = data
            self.start = data.startIndex
        }

        mutating func next() -> String? {
            guard start < data.endIndex else { return nil }
            var end = start
            while end < data.endIndex, data[end] != 0x0A {
                data.formIndex(after: &end)
            }
            defer { start = end < data.endIndex ? data.index(after: end) : end }
            return String(decoding: data[start..<end], as: UTF8.self)
        }
    }
}
