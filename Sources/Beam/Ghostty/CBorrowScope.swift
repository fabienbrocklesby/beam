import Foundation

/// C copies of Swift values for a libghostty call that borrows them for its
/// duration. Every copy is freed when the scope's body returns.
struct CBorrowScope {
    private var allocations: [UnsafeMutablePointer<CChar>] = []

    static func with<Result>(_ body: (inout CBorrowScope) -> Result) -> Result {
        var scope = CBorrowScope()
        defer {
            for allocation in scope.allocations { allocation.deallocate() }
        }
        return body(&scope)
    }

    /// A NUL-terminated copy of `string`.
    mutating func copy(_ string: String) -> UnsafePointer<CChar> {
        let utf8 = string.utf8CString
        let pointer = allocate(count: utf8.count)
        _ = UnsafeMutableBufferPointer(start: pointer, count: utf8.count).initialize(from: utf8)
        return UnsafePointer(pointer)
    }

    /// A copy of `data`'s bytes. Empty data still gets a valid pointer.
    mutating func copy(_ data: Data) -> UnsafePointer<CChar> {
        let pointer = allocate(count: data.count)
        UnsafeMutableRawBufferPointer(start: pointer, count: data.count).copyBytes(from: data)
        return UnsafePointer(pointer)
    }

    private mutating func allocate(count: Int) -> UnsafeMutablePointer<CChar> {
        let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: max(count, 1))
        allocations.append(pointer)
        return pointer
    }
}
