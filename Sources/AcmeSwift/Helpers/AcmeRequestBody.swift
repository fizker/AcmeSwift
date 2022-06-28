import Foundation
import Crypto
import JWTKit

/*
Example request body:
 {
     "protected": base64url({
         "alg": "ES256",
         "jwk": {...},
         "nonce": "6S8IqOGY7eL2lsGoTZYifg",
         "url": "https://example.com/acme/new-account"
     }),
     "payload": base64url({
         "termsOfServiceAgreed": true,
         "contact": [
            "mailto:cert-admin@example.org",
            "mailto:admin@example.org"
         ]
     }),
     "signature": "RZPOnYoPs1PhjszF...-nh6X1qtOFPB519I"
 }
*/

/// All requests to the ACMEv2 server must have their body wrapped into a custom JWS format
struct AcmeRequestBody<T: EndpointProtocol>: Encodable {
    var protected: ProtectedHeader
    
    var payload: T.Body
    
    private var signature: String = ""
    
    private var privateKey: Crypto.P256.Signing.PrivateKey
    
    enum CodingKeys: String, CodingKey {
        case protected
        case payload
        case signature
    }
    
    struct ProtectedHeader: Codable {
        internal init(alg: Algorithm = .es256, jwk: JWK? = nil, kid: String? = nil, nonce: String, url: URL) {
            self.alg = alg
            self.jwk = jwk
            self.kid = kid
            self.nonce = nonce
            self.url = url
        }
        
        var alg: Algorithm = .es256
        var jwk: JWK?
        var kid: String?
        var nonce: String
        var url: URL
        
        enum Algorithm: String, Codable {
            case es256 = "ES256"
        }
        
        struct JWK: Codable {
            /// Key Type
            var kty: KeyType = .ec
            
            /// Curve
            var crv: CurveType = .p256
            
            /// The x coordinate for the Elliptic Curve point.
            var x: String
            
            /// The y coordinate for the Elliptic Curve point.
            var y: String
            
            enum KeyType: String, Codable {
                case ec = "EC"
                case rsa = "RSA"
                case oct
            }
            
            enum CurveType: String, Codable {
                case p256 = "P-256"
            }
        }
    }
    
    init(privateKey: Crypto.P256.Signing.PrivateKey, nonce: String, payload: T) throws {
        self.privateKey = privateKey
        
        let pubKey = try JWTKit.ECDSAKey.public(pem: privateKey.publicKey.pemRepresentation)
        guard let parameters = pubKey.parameters else {
            throw AcmeUnspecifiedError.invalidKeyError("Public key parameters are nil")
        }
        print("\n••••  x=\(parameters.x.fromBase64Url()), y=\(parameters.y.fromBase64Url())")
        
        //let xData = Data(string: parameters.x, options: Data.Base64DecodingOptions.ignoreUnknownCharacters)
        //let yData = Data(string: parameters.y, options: Data.Base64DecodingOptions.ignoreUnknownCharacters)
        let xData = parameters.x.data(using: .utf8)
        let yData = parameters.y.data(using: .utf8)
        
         
        print("\n xData=\(xData), yData=\(yData)")
        print("\n•••• decoded x=\(String(data: xData!, encoding: .utf8)), y=\(String(data: yData!, encoding: .utf8))")
             
        let x = parameters.x //String(data: xData!, encoding: .utf8)!
        let y = parameters.y //String(data: yData!, encoding: .utf8)!
        
        
        
        self.protected = .init(
            alg: .es256,
            jwk: .init(
                // "Parse error reading JWS: EC public key has incorrect padding"
                x: x, //.padding(toLength: 32, withPad: "=", startingAt: 0),
                y: y //.padding(toLength: 32, withPad: "=", startingAt: 0)
            ),
            nonce: nonce,
            url: payload.url
        )
        self.payload = payload.body ?? (NoBody.init() as! T.Body)
        
        print("\n •••• parameters.x length=\(parameters.x.count) value=\(x)")
        print("\n •••• parameters.y length=\(parameters.y.count) value=\(y)")
    }
    
    /// Encode as a JWT as  described in ACMEv2 (RFC 8555)
    func encode(to encoder: Encoder) throws {
        let jsonEncoder = JSONEncoder()
        
        let protectedData = try jsonEncoder.encode(self.protected)
        guard let protectedJson = String(data: protectedData, encoding: .utf8) else {
            throw AcmeUnspecifiedError.jwsEncodeError("Unable to encode AcmeRequestBody.protected as JSON string")
        }
        let protectedBase64 = protectedJson.toBase64Url()
        
        let payloadData = try jsonEncoder.encode(self.payload)
        guard let payloadJson = String(data: payloadData, encoding: .utf8) else {
            throw AcmeUnspecifiedError.jwsEncodeError("Unable to encode AcmeRequestBody.payload as JSON string")
        }
        let payloadBase64 = payloadJson.toBase64Url()
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protectedBase64, forKey: .protected)
        try container.encode(payloadBase64, forKey: .payload)
        
        let signedString = "\(protectedBase64).\(payloadBase64)"
        //guard let signedData = signedString.toBase64Url().data(using: .utf8) else {
        guard let signedData = signedString.data(using: .utf8) else {
            throw AcmeUnspecifiedError.jwsEncodeError("Unable to encode data to sign String as Data")
        }
        print("\n••••• signedString=\(signedString), signedData=\(signedData)")
        print("\n •••••• Private key: \(privateKey.pemRepresentation)")
        
        let signature = try self.privateKey.signature(for: signedData)
        let signatureData = signature.rawRepresentation
        
        //print("\n••••• signature raw s
        //print("\n••••• signature raw string=\(String(data: signatureData, encoding: .utf8)), data=\(signatureData.base64EncodedString())")
        
        /*guard let signatureBase64 = String(data: signatureData, encoding: .utf8)?.toBase64Url() else {
            throw AcmeUnspecifiedError.jwsEncodeError("Unable to get signed data string as String")
        }*/
        let signatureBase64 = signatureData.toBase64UrlString()
        try container.encode(signatureBase64, forKey: .signature)
        
    }
    
    struct NoBody: Codable {
        init(){}
    }
}
