## ADDED Requirements

### Requirement: Verified SDK request
The bridge SHALL request only `/video/modules` for hotRank with string categoryId, positive pageIndex and pageSize. The UI SHALL send pageIndex=1 and pageSize=20. SDK crypto and persistent identity MUST be reused.
#### Scenario: Invalid page or missing category
- **WHEN** a request supplies pageIndex=0 or omits categoryId
- **THEN** it is rejected before any upstream request.

### Requirement: Server order and title preservation
The system SHALL select module MOD_818368, preserve its name and first ten items in original order, retain string video IDs, and assign positions 1..10 from original indices. It MUST NOT sort, deduplicate or filter the ranking by playCount, score, weight, sortOrder or genre. Exposed window and metric SHALL be null.
#### Scenario: Rank disagrees with cumulative count
- **WHEN** item 2 has fewer cumulative views than item 3
- **THEN** their positions remain 2 and 3 and the server title is displayed verbatim.

### Requirement: Category isolation
The system SHALL fetch and cache by actual categoryId; recommendation and popular use 0. A category without a valid source mapping MUST NOT receive the all-site ranking.
#### Scenario: Switch category during pending request
- **WHEN** category A finishes after the user switches to B
- **THEN** A populates only its own cache and cannot appear under B.

### Requirement: Independent progressive state
Rank loading SHALL be independent of catalog, pagination and other home content. The UI SHALL show skeletons during initial loading, retry on failure, an explicit empty state if no module exists, and the previous ranking if a refresh fails.
#### Scenario: Ranking is slow or fails
- **WHEN** catalog succeeds before the ranking
- **THEN** catalog remains usable and ranking owns its loading/error state.

### Requirement: Ranked card interaction
Ranked cards SHALL display the original position, preserve source identity, and open the existing source detail/player flow without converting to Bangumi IDs.
#### Scenario: Open an item beyond first three
- **WHEN** the user horizontally scrolls and taps rank 10
- **THEN** the original MioMedia video opens through the existing detail callback.

### Requirement: Live evidence
Delivery SHALL include SDK selftest, supplied hot_rank_probe output comparison, two consecutive equal-order calls, a category different from 0, focused tests and Web runtime verification.
#### Scenario: Consecutive responses update cumulative counts
- **WHEN** playCount changes between consecutive calls
- **THEN** the implementation still matches the original item order and reports no client sorting.
