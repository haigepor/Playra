## ADDED Requirements

### Requirement: Explicit platform runtime endpoint
The system SHALL route explicit runtime rule requests through a shared HTTP client. Web SHALL use a fixed same-origin endpoint; Android SHALL require a configured endpoint and SHALL reject insecure production configuration.

#### Scenario: Native runtime is not configured
- **WHEN** a runtime rule is called without a native endpoint
- **THEN** it fails with RUNTIME_UNAVAILABLE without a request to localhost or a source website

#### Scenario: Ordinary anime rule
- **WHEN** a request does not use the reserved runtime host
- **THEN** the existing request executor receives the unchanged request

### Requirement: Controlled adapter protocol
The runtime SHALL expose versioned health, adapter manifests, search, episodes and resolve operations for registered adapters only. The default template SHALL advertise no content capabilities and SHALL never manufacture film resources.

#### Scenario: Template operation
- **WHEN** search or resolve is requested on the unimplemented template
- **THEN** a structured UNSUPPORTED error is returned

#### Scenario: Unknown adapter or route
- **WHEN** an unknown adapter, route, method or script request is submitted
- **THEN** it fails explicitly and no arbitrary script or destination is executed

### Requirement: Fixed Web forwarding
The Web bridge SHALL be opt-in, forward only approved routes to a fixed loopback runtime, bound request and response sizes, impose a timeout, and cancel forwarding when its client disconnects.

#### Scenario: Runtime is disabled
- **WHEN** the bridge is called before enabling a runtime port
- **THEN** RUNTIME_UNAVAILABLE is returned without generic private-network proxying

#### Scenario: Oversized request
- **WHEN** a body exceeds the configured size bound
- **THEN** it is rejected and not forwarded

### Requirement: Cancellation and error preservation
The client SHALL propagate cancellation and bounded deadlines. The Python adapter context SHALL provide cooperative cancellation and time limits. Structured runtime errors SHALL survive the shared source-service boundary and SHALL not be interpreted as no resources.

#### Scenario: Cancelled source request
- **WHEN** a request is cancelled while waiting for a runtime result
- **THEN** no successful stale result is published

#### Scenario: Decryption fails
- **WHEN** an adapter returns DECRYPT_ERROR
- **THEN** that error remains distinguishable from an empty successful search result

### Requirement: Demonstrable integration skeleton
The project SHALL provide startup instructions and an uninstalled example rule. Verification SHALL exercise real HTTP and RuleEngine integration, legacy non-runtime regression and Web/Android compilation, while stating the limits of native-device playback evidence.

#### Scenario: Fixture protocol integration
- **WHEN** the isolated fixture adapter is used
- **THEN** search pagination, episode labels, resolve headers and expiry can traverse the actual shared rule pipeline
