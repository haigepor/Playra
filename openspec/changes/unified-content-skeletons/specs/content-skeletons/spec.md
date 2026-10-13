## ADDED Requirements

### Requirement: Independent content skeletons
The application SHALL show layout-shaped skeletons while a content section is loading with no loaded data, covering modern discovery channels, film categories, browse/search results, calendar entries, episode catalogs and related work sections.

#### Scenario: A movie channel is pending
- **WHEN** movie loading is active and the channel has no videos
- **THEN** poster skeletons occupy its future cards instead of a progress line and an empty loading sentence

#### Scenario: Another channel completes first
- **WHEN** anime content is available while movie loading is pending
- **THEN** anime videos remain visible and only movie placeholders continue loading

### Requirement: Preserve loaded content
The application SHALL preserve visible content while refreshing and SHALL append finite skeletons at the list tail during pagination.

#### Scenario: Pagination waits
- **WHEN** a nonempty film list requests another page
- **THEN** current video identities and cards remain and loading placeholders appear after them

### Requirement: Distinct terminal states
The application SHALL stop content skeletons when loading ends and SHALL retain empty, failure and retry feedback.

#### Scenario: Empty response
- **WHEN** a completed request returns no items
- **THEN** the section shows an empty state without animated skeletons

#### Scenario: Request failure
- **WHEN** a request fails
- **THEN** error and retry remain available without an endless skeleton

### Requirement: Image loading lifecycle
The shared network image widget SHALL show a themed image skeleton only while an image request is pending and SHALL retain static missing-image presentation for an empty address or request failure.

#### Scenario: Image waits after title loads
- **WHEN** card data is loaded but its cover request is pending
- **THEN** only the cover area has skeleton motion and real card text remains visible

#### Scenario: Invalid image address
- **WHEN** the cover is empty or fails to load
- **THEN** a static fallback appears instead of continuing loading animation

### Requirement: Accessible restrained motion
Skeleton placeholders SHALL be noninteractive, provide one loading accessibility label per group, follow theme colors and stop animation when reduced motion is enabled.

#### Scenario: Reduced motion
- **WHEN** the device disables animations
- **THEN** skeleton geometry remains visible with static color and no repeated animation

### Requirement: Preserve operational feedback
The application SHALL retain authentic playback parsing, download, mutation and synchronization progress and SHALL render locally available profile, library and settings data immediately.

#### Scenario: Playback parses while content exists
- **WHEN** the player resolves a selected episode
- **THEN** authentic parsing feedback and the existing playback session remain unchanged
