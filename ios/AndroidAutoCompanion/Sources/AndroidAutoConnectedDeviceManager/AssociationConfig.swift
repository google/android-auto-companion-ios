import CoreBluetooth

/// A `struct` that specifies different options for association.
public struct AssociationConfig {
  /// The UUID to look for during association scans.
  public var associationUUID: CBUUID
}
