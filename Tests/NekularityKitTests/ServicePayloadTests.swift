import Foundation
import Testing
@testable import NekularityKit

/// An empty payload means "nothing", which a method taking no arguments expects.
@Test func anEmptyPayloadIsNull() {
    #expect(ServicePayload.normalized("") == "null")
    #expect(ServicePayload.normalized("   \n\t ") == "null")
    #expect(ServicePayload.normalized(" {\"a\":1} ") == "{\"a\":1}")
}

/// Text that is not JSON is caught here, so the service is never asked to
/// interpret it and the person is told before anything is sent.
@Test func textThatIsNotJSONIsRejected() {
    for bad in ["{oops", "{\"a\":}", "[1,2", "not json", "\"unterminated"] {
        #expect(ServicePayload.isValid(bad) == false, "\(bad) was accepted as JSON")
    }
}

@Test func realJSONIsAccepted() {
    for good in ["null", "{}", "[]", "{\"hello\":\"world\"}", "42", "true", "\"text\"", ""] {
        #expect(ServicePayload.isValid(good) == true, "\(good) was rejected")
    }
}
