import Foundation

/// Wire models for the EVE Voice Gateway's REST surface (GW-M1). Field names
/// are Swift-idiomatic camelCase; `GatewayAPIClient` decodes/encodes with
/// snake_case conversion to match the Gateway's pydantic models exactly
/// (eve-os `eve/gateway/schemas.py`) without duplicating a CodingKeys block
/// per type.

struct PairingRequestView: Decodable {
    let id: String
    let deviceName: String
    let deviceModel: String
    let status: String
    let requestedAt: String
    let decidedAt: String?
    let expiresAt: String
}

struct PairingClaimResult: Decodable {
    let credential: String
}

struct SessionTicket: Decodable {
    let sessionId: String
    let ticket: String
    let expiresAt: String
}
