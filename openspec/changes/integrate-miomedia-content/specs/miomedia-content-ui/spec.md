## ADDED Requirements
### Requirement: Verified content parameters
The service SHALL accept keyword search and categoryId catalog filtering with positive pageIndex/pageSize and SHALL preserve string video identities.
#### Scenario: Search pagination metadata is incomplete
- **WHEN** pages is zero while total indicates another page
- **THEN** the next page remains available based on total and page size.
### Requirement: Independent content domain
The UI SHALL classify source content from actual category metadata and SHALL never convert a MioMedia ID to a Bangumi identity.
#### Scenario: Unknown classification
- **WHEN** metadata does not establish a supported category
- **THEN** content does not appear in an unrelated named category.
### Requirement: Progressive home and detail
The modern home SHALL publish source sections independently of anime loading and SHALL open a source detail view with real lines and episodes.
#### Scenario: Source is unavailable
- **WHEN** the runtime cannot provide content
- **THEN** source sections offer retry while anime remains usable.
### Requirement: Explicit playback boundary
The system MUST not execute unspecified remote scripts or falsify ad completion. It SHALL use the supplied self-developed SDK playback implementation and return ready, ad_required or unavailable. Identity maintenance SHALL be explicit and separate from playback retry.
#### Scenario: Playback needs platform integration
- **WHEN** exchange requires valid ad verification
- **THEN** the detail page displays the requirement without automatically replacing device identity.
#### Scenario: SDK resolves a real media URL
- **WHEN** the supplied SDK returns ready media for the selected video, line and episode
- **THEN** the same page session opens the media using existing platform resource handling and retains the real episode identity.
#### Scenario: Exchange response is lost
- **WHEN** a network error happens during the token-consuming exchange
- **THEN** the wrapper does not automatically resubmit exchange.
#### Scenario: Maintenance negotiation fails
- **WHEN** explicit identity maintenance cannot verify the new session
- **THEN** the persisted original identity is preserved.
