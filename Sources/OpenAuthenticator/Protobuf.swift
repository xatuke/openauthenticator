import Foundation

enum ProtobufValue {
    case varint(UInt64)
    case bytes(Data)
}

struct ProtobufField {
    let number: Int
    let value: ProtobufValue
}

enum Protobuf {
    static func parse(_ data: Data) -> [ProtobufField] {
        var fields: [ProtobufField] = []
        var pos = 0
        let bytes = Array(data)

        while pos < bytes.count {
            guard let (tag, newPos) = decodeVarint(bytes, from: pos) else { break }
            pos = newPos
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)

            switch wireType {
            case 0: // varint
                guard let (value, newPos) = decodeVarint(bytes, from: pos) else { return fields }
                pos = newPos
                fields.append(ProtobufField(number: fieldNumber, value: .varint(value)))
            case 2: // length-delimited
                guard let (length, newPos) = decodeVarint(bytes, from: pos) else { return fields }
                pos = newPos
                let end = pos + Int(length)
                guard end <= bytes.count else { return fields }
                fields.append(ProtobufField(number: fieldNumber, value: .bytes(Data(bytes[pos..<end]))))
                pos = end
            default:
                return fields
            }
        }

        return fields
    }

    private static func decodeVarint(_ bytes: [UInt8], from start: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var pos = start

        while pos < bytes.count {
            let b = bytes[pos]
            result |= UInt64(b & 0x7F) << shift
            pos += 1
            if b & 0x80 == 0 { return (result, pos) }
            shift += 7
            if shift >= 64 { return nil }
        }

        return nil
    }
}
