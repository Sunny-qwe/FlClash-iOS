public func MobileSetMitmPressure(_ level: Int32) {}
public func MobileForceGC() {}
public func MobileGetMemoryDiagnostics() -> String {
  "{\"heap-allocated-bytes\":1234,\"mitm\":{\"active-scripts\":1}}"
}
