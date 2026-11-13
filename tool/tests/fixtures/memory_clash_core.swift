public func MobileSetMitmPressure(_ level: Int32) {}
public func MobileForceGC() {}
public func MobileReportMemoryFootprint(_ bytes: Int64) {}
public func MobileGetMemoryDiagnostics() -> String {
  "{\"heap-allocated-bytes\":1234,\"mitm\":{\"active-scripts\":1},\"events\":[{\"kind\":\"script.start\"}]}"
}
public func MobileRequestMemoryProfile(_ directory: String, _ runID: String, _ kind: String) -> Bool { true }
