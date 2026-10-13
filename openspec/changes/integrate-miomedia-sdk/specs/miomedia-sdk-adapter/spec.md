## ADDED Requirements

### Requirement: Unchanged SDK algorithms
The adapter SHALL reuse the standard-library SDK and preserve its algorithm modules and binary resource byte-for-byte. Only profile/config environment annotations SHALL differ.
#### Scenario: SDK verification
- **WHEN** the vendored SDK is checked
- **THEN** algorithm hashes match the supplied package and its selftest passes

### Requirement: Stable local service session
The adapter SHALL persist one local-service identity, strictly verify negotiate secrets and business success, preserve corrected clock state, and merge concurrent initialization.
#### Scenario: Restart
- **WHEN** the facade restarts with the same identity path
- **THEN** it reuses the same device ID
#### Scenario: Invalid secret
- **WHEN** negotiate returns a mismatched secret
- **THEN** no content request is issued and SESSION_MISMATCH is reported

### Requirement: Restricted SDK facade
The runtime SHALL expose a fixed MioMedia SDK operation endpoint to Web and native clients. It SHALL reject arbitrary paths, writes, extra arguments and unimplemented search. Health SHALL not trigger network initialization.
#### Scenario: Approved content request
- **WHEN** recommend is called through the runtime
- **THEN** the SDK decrypts the upstream response and returns content without handshake secrets
#### Scenario: Unsupported operation
- **WHEN** a client submits an account write or raw URL
- **THEN** the request is rejected before upstream execution

### Requirement: Error and cancellation boundaries
The facade SHALL distinguish network failures, timeout, cancellation, business rejection and decryption failure. It SHALL bound retries to one additional attempt for network errors only.
#### Scenario: Business failure
- **WHEN** HTTP 200 contains an unsuccessful business envelope
- **THEN** it is not interpreted as an empty resource list or retried
#### Scenario: Cancelled request
- **WHEN** a request is cancelled while SDK execution is active
- **THEN** the result is not published as success

### Requirement: Evidence-based endpoint inventory
The delivery SHALL enumerate unique documented endpoints, their purposes and data evidence, and distinguish successful protocol exchange from a playable media address.
#### Scenario: Client parsing response
- **WHEN** exchange returns an empty playUrl and client parsing materials
- **THEN** the delivery records the missing playback capability without executing the supplied script
