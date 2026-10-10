## ADDED Requirements

### Requirement: Versioned HTTP source endpoints
The system SHALL offer runnable /api/v1 source, category, directory, search, content and line endpoints with consistent JSON DTOs and errors.

#### Scenario: Search then retrieve lines
- **WHEN** an HTTP client searches a configured source and selects an opaque content ID
- **THEN** it can retrieve that content's lines through the shared RuleEngine without submitting an arbitrary upstream URL

### Requirement: Isolated asynchronous browser operations
The system SHALL expose resolution/challenge creation, polling and cancellation with expiring session-owned handles, using the existing browser backend.

#### Scenario: Resolution lifecycle
- **WHEN** a client starts and polls a resolution
- **THEN** it receives pending, ready, challenge_required, failed or cancelled state and ready includes media format and permitted playback context

### Requirement: HTTP input and execution boundaries
The system SHALL default to loopback, limit payloads/concurrency, validate source references, protect session isolation, and omit credentials/raw debug responses from public DTOs.

#### Scenario: Invalid reference or payload
- **WHEN** a request contains an unknown source/content ID, invalid paging, an oversized body or another session's handle
- **THEN** it returns a structured appropriate HTTP error without executing an arbitrary upstream request

### Requirement: Repeatable API verification and documentation
The system SHALL include documented startup/call examples and localhost integration coverage independent of third-party site availability.

#### Scenario: Deterministic API fixture
- **WHEN** the integration suite executes against local XPath/API fixtures
- **THEN** listing, search, episode retrieval, pagination, error mapping, cancellation and session behavior can be verified without public websites
