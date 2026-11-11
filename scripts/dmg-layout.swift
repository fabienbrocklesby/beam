// Writes the .DS_Store that lays out the disk image window: its size, the
// background picture, and where the app and the Applications link sit.
//
// Finder keeps these as records in a B-tree inside a buddy-allocated file.
// The background is an Alias Manager record that names a file on the mounted
// volume by its catalog IDs and dates, so this runs against the mounted image
// once the files are in place. The formats follow dmgbuild's ds_store and
// mac_alias (MIT), which document them from Finder's own files.
//
// Usage: dmg-layout <mounted volume>

import Foundation

/// The window, in points. The background art is drawn for this geometry.
enum Layout {
    static let windowBounds = "{{200, 120}, {640, 400}}"
    static let iconSize = 128.0
    static let textSize = 13.0
    static let background = ".background/background.tiff"
    /// Icon centres, from the top left of the window's content.
    static let icons: [(name: String, x: UInt32, y: UInt32)] = [
        ("Applications", 480, 190),
        ("Beam.app", 160, 190),
    ]
}

struct LayoutError: Error, CustomStringConvertible {
    let description: String
}

/// Big-endian bytes, the byte order of both formats.
struct Bytes {
    var data = Data()

    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func u16(_ value: UInt16) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
    mutating func u64(_ value: UInt64) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
    mutating func i16(_ value: Int16) { u16(UInt16(bitPattern: value)) }
    mutating func append(_ bytes: Data) { data.append(bytes) }
    mutating func code(_ fourCharacters: String) { data.append(contentsOf: Array(fourCharacters.utf8.prefix(4))) }
    mutating func zeros(_ count: Int) { data.append(Data(count: count)) }

    /// A Pascal string in a fixed field: a length byte, then the bytes, zero padded.
    mutating func pascal(_ bytes: Data, field: Int) {
        let kept = bytes.prefix(field - 1)
        u8(UInt8(kept.count))
        append(kept)
        zeros(field - 1 - kept.count)
    }

    /// An alias extension: tag, length, value, padded to an even length.
    mutating func tagged(_ tag: Int16, _ value: Data) {
        i16(tag)
        u16(UInt16(value.count))
        append(value)
        if value.count % 2 == 1 { u8(0) }
    }
}

/// Seconds from the Mac epoch (1904) to the Unix epoch (1970).
let macEpochOffset = 2_082_844_800.0

func macSeconds(_ date: Date) -> Double { date.timeIntervalSince1970 + macEpochOffset }

func attributes(_ path: String) throws -> (cnid: UInt32, created: Date) {
    let values = try FileManager.default.attributesOfItem(atPath: path)
    guard let number = values[.systemFileNumber] as? NSNumber, let created = values[.creationDate] as? Date else {
        throw LayoutError(description: "no file number or creation date for \(path)")
    }
    // On HFS+ the inode number is the catalog node ID.
    return (UInt32(truncatingIfNeeded: number.uint64Value), created)
}

/// A version 2 alias to a file one folder below the volume root, as Finder
/// writes for a window background on an HFS+ volume.
func alias(to relativePath: String, onVolume volume: String) throws -> Data {
    let folderName = (relativePath as NSString).deletingLastPathComponent
    let fileName = (relativePath as NSString).lastPathComponent
    guard let volumeName = try URL(fileURLWithPath: volume).resourceValues(forKeys: [.volumeNameKey]).volumeName
    else { throw LayoutError(description: "no volume name for \(volume)") }
    let volumeCreated = try attributes(volume).created
    let folder = try attributes((volume as NSString).appendingPathComponent(folderName))
    let file = try attributes((volume as NSString).appendingPathComponent(relativePath))

    let utf8 = { (string: String) in Data(string.utf8) }
    var bytes = Bytes()
    bytes.zeros(4)  // creator
    bytes.u16(0)  // record size, set below
    bytes.u16(2)  // version
    bytes.u16(0)  // kind: file
    bytes.pascal(utf8(volumeName), field: 28)
    bytes.u32(UInt32(macSeconds(volumeCreated)))
    bytes.code("H+")
    bytes.u16(0)  // fixed disk
    bytes.u32(folder.cnid)
    bytes.pascal(utf8(fileName), field: 64)
    bytes.u32(file.cnid)
    bytes.u32(UInt32(macSeconds(file.created)))
    bytes.zeros(8)  // type and creator codes
    bytes.i16(-1)  // levels from
    bytes.i16(-1)  // levels to
    bytes.u32(0)  // volume attributes
    bytes.zeros(2)  // volume file system ID
    bytes.zeros(10)

    // Extensions, in the order Finder writes them.
    bytes.tagged(0, utf8(folderName))
    var dates = Bytes()
    dates.u64(UInt64(macSeconds(volumeCreated) * 65536))
    bytes.tagged(16, dates.data)
    dates = Bytes()
    dates.u64(UInt64(macSeconds(file.created) * 65536))
    bytes.tagged(17, dates.data)
    var path = Bytes()
    path.u32(folder.cnid)
    bytes.tagged(1, path.data)
    bytes.tagged(2, utf8("\(volumeName):\(folderName):\u{0}\(fileName)"))
    for (tag, name) in [(Int16(14), fileName), (15, volumeName)] {
        var unicode = Bytes()
        unicode.u16(UInt16(name.utf16.count))
        for unit in name.utf16 { unicode.u16(unit) }
        bytes.tagged(tag, unicode.data)
    }
    bytes.tagged(18, utf8("/" + relativePath))
    bytes.tagged(19, utf8(volume))
    bytes.i16(-1)
    bytes.u16(0)

    var record = bytes.data
    let size = UInt16(record.count).bigEndian
    withUnsafeBytes(of: size) { record.replaceSubrange(4..<6, with: $0) }
    return record
}

/// One Finder record: a file name, a four character property code and a value.
struct Record {
    enum Value {
        case long(UInt32)
        case type(String)
        case blob(Data)
    }

    let name: String
    let code: String
    let value: Value

    var bytes: Data {
        var bytes = Bytes()
        bytes.u32(UInt32(name.utf16.count))
        for unit in name.utf16 { bytes.u16(unit) }
        bytes.code(code)
        switch value {
        case .long(let number):
            bytes.code("long")
            bytes.u32(number)
        case .type(let code):
            bytes.code("type")
            bytes.code(code)
        case .blob(let data):
            bytes.code("blob")
            bytes.u32(UInt32(data.count))
            bytes.append(data)
        }
        return bytes.data
    }
}

func plist(_ object: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
}

/// A buddy-allocated file holding one B-tree with a single leaf.
///
/// Allocator offsets start 4 bytes into the file. The 32-byte header takes
/// offset 0, which splits the 2GB space into one free block of every size;
/// the root block takes the 2KB block at 2048, the B-tree header the other
/// 32-byte block at 32, and the leaf the 4KB block at 4096. The free lists
/// record what is left, so Finder can extend the file if the volume is ever
/// writable.
func dsStore(_ records: [Record]) throws -> Data {
    let sorted = records.sorted {
        let (left, right) = ($0.name.lowercased(), $1.name.lowercased())
        return left == right ? Array($0.code.utf8).lexicographicallyPrecedes(Array($1.code.utf8)) : left < right
    }
    var leaf = Bytes()
    leaf.u32(0)  // no child: a leaf
    leaf.u32(UInt32(sorted.count))
    for record in sorted { leaf.append(record.bytes) }
    guard leaf.data.count <= 4096 else { throw LayoutError(description: "records overflow one B-tree node") }

    var tree = Bytes()
    tree.u32(2)  // root node: block 2
    tree.u32(0)  // levels above the leaf
    tree.u32(UInt32(sorted.count))
    tree.u32(1)  // nodes
    tree.u32(0x1000)  // node size

    // A block address is its offset with log2 of its size in the low 5 bits.
    let blocks: [UInt32] = [2048 | 11, 32 | 5, 4096 | 12]
    var root = Bytes()
    root.u32(UInt32(blocks.count))
    root.u32(0)
    for block in blocks { root.u32(block) }
    root.zeros(4 * (256 - blocks.count))
    root.u32(1)  // table of contents: one entry
    root.u8(4)
    root.code("DSDB")
    root.u32(1)
    for width in 0..<32 {
        let free = (6...10).contains(width) || (13...30).contains(width)
        root.u32(free ? 1 : 0)
        if free { root.u32(1 << width) }
    }

    var file = Data(count: 4 + 8192)
    func put(_ bytes: Data, at offset: Int) { file.replaceSubrange(4 + offset..<4 + offset + bytes.count, with: bytes) }
    var header = Bytes()
    header.u32(1)
    header.code("Bud1")
    header.u32(2048)  // root block offset
    header.u32(2048)  // root block size
    header.u32(2048)  // root block offset, again
    header.append(Data([0, 0, 0x10, 0x0C, 0, 0, 0, 0x87, 0, 0, 0x20, 0x0B, 0, 0, 0, 0]))
    file.replaceSubrange(0..<header.data.count, with: header.data)
    put(root.data, at: 2048)
    put(tree.data, at: 32)
    put(leaf.data, at: 4096)
    return file
}

func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 2 else { throw LayoutError(description: "usage: dmg-layout <mounted volume>") }
    let volume = arguments[1]

    let window: [String: Any] = [
        "WindowBounds": Layout.windowBounds,
        "ShowStatusBar": false, "ShowToolbar": false, "ShowPathbar": false, "ShowSidebar": false,
        "ShowTabView": false, "ContainerShowSidebar": false, "PreviewPaneVisibility": false,
        "SidebarWidth": 180,
    ]
    let iconView: [String: Any] = [
        "viewOptionsVersion": 1,
        "backgroundType": 2,  // a picture
        "backgroundImageAlias": try alias(to: Layout.background, onVolume: volume),
        "iconSize": Layout.iconSize, "textSize": Layout.textSize, "labelOnBottom": true,
        "arrangeBy": "none", "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        "showIconPreview": false, "showItemInfo": false, "scrollPositionX": 0.0, "scrollPositionY": 0.0,
    ]
    var records = [
        Record(name: ".", code: "vSrn", value: .long(1)),
        Record(name: ".", code: "bwsp", value: .blob(try plist(window))),
        Record(name: ".", code: "icvp", value: .blob(try plist(iconView))),
        Record(name: ".", code: "icvl", value: .type("icnv")),
    ]
    for icon in Layout.icons {
        var location = Bytes()
        location.u32(icon.x)
        location.u32(icon.y)
        location.u32(0xFFFF_FFFF)
        location.u32(0xFFFF_0000)
        records.append(Record(name: icon.name, code: "Iloc", value: .blob(location.data)))
    }
    try dsStore(records).write(to: URL(fileURLWithPath: volume).appendingPathComponent(".DS_Store"))
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("dmg-layout: \(error)\n".utf8))
    exit(1)
}
