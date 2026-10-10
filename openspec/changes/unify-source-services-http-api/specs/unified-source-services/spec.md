## ADDED Requirements

### Requirement: Compatible source identity and models
The system SHALL assign stable source identities, expose explicit capabilities and typed content/line/episode models, and preserve legacy JSON import/export including inactive API configuration.

#### Scenario: Legacy rule round trip
- **WHEN** an existing XPath or API rule is imported, executed and exported
- **THEN** its prior fields and behavior are preserved and additive identity/configuration fields remain compatible

### Requirement: Shared search and episode execution
The system SHALL execute XPath/API searches and episodes through the existing RuleEngine behind a shared service used by application callers and HTTP, with bounded aggregation and typed failures.

#### Scenario: Mixed modes and partial failures
- **WHEN** multiple sources with mixed search/chapter modes are queried
- **THEN** results retain source identity, individual failures remain distinguishable from empty results, and cancellation prevents stale publication

### Requirement: Directory capabilities and classification
The system SHALL register directory adapters outside presentation, preserve the current read-only bundled fallback and classify content using explicit source or metadata evidence.

#### Scenario: Unsupported directory
- **WHEN** a source without a directory adapter is requested
- **THEN** the service returns UNSUPPORTED and does not invent category content

### Requirement: Honest pagination and operation health
The system SHALL expose pagination mode and operation-specific health timestamps, distinguishing local collection slicing from upstream pagination.

#### Scenario: Fixed-page legacy source
- **WHEN** a rule does not configure upstream paging
- **THEN** the response identifies local pagination and does not claim an upstream total or unseen next page

### Requirement: Platform resolution and challenge context
The system SHALL preserve Android/Windows/Web resolution implementations behind a context-aware interface and isolate challenge cookies/User-Agent by source and session.

#### Scenario: Cancelled resolution
- **WHEN** a caller cancels or replaces a resolution
- **THEN** its result cannot overwrite the active request and any owned browser resources are released

#### Scenario: Challenge continuation
- **WHEN** a source requires verification
- **THEN** a typed challenge context is returned and verified context can resume the original source operation without exposing cookies in public results
