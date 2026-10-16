## ADDED Requirements

### Requirement: Lumina content priority
The application SHALL prioritize Lumina for anime browsing, search primary data, detail and playback while retaining existing providers and strict work matching.

#### Scenario: Providers finish in a different order
- **WHEN** a lower priority provider returns before Lumina for the same strictly matched work
- **THEN** primary title and cover SHALL still use Lumina when its result arrives.

#### Scenario: Lumina is unavailable
- **WHEN** Lumina content cannot be loaded
- **THEN** the existing anime entry SHALL remain usable and retry SHALL remain available.

#### Scenario: Movie SDK also returns anime
- **WHEN** MioMedia returns verified anime metadata
- **THEN** the content SHALL remain classified as anime with lower provider priority than dedicated anime sources, and SHALL NOT replace available Lumina as the default source.

### Requirement: Lumina resolution selection
The application SHALL prefer declared 4K then 1080p media from Lumina while preserving the original play-format and part parameters. It MUST NOT manufacture a quality request parameter or label an unclassified single URL as 4K.

#### Scenario: Resolver returns 1080p before 4K
- **WHEN** the same Lumina line and episode returns both declared resolutions
- **THEN** preparation SHALL select 4K regardless of resolver array order and preserve its exact request headers.

#### Scenario: A manually selected line fails at 4K
- **WHEN** the selected line also offers 1080p and its 4K media fails
- **THEN** playback MAY retry 1080p within that line without unlocking the line or switching episodes.

#### Scenario: Legacy resolver has no resolution fields
- **WHEN** Lumina returns a single MP4 URL without declared resolution
- **THEN** the URL SHALL remain usable with unknown quality until actual decoder dimensions are available.

### Requirement: Original content and episode identities
The application MUST retain source video IDs as strings and original play-format and part references, and MUST NOT manufacture Bangumi IDs or numeric episode identities from list positions.

#### Scenario: A special episode has no numeric episode number
- **WHEN** a part is named as a special or a date
- **THEN** playback SHALL receive that original part reference and selection SHALL not collide with another special.

### Requirement: Restricted SDK execution
The runtime SHALL expose only fixed Lumina content operations, preserve media headers including empty User-Agent, persist one device fingerprint per installation and reuse one Client per worker thread.

#### Scenario: Untrusted runtime request specifies a host or script
- **WHEN** a caller adds arbitrary host, module or script parameters
- **THEN** the runtime SHALL reject the request without executing it.

#### Scenario: SDK returns internal diagnostic data
- **WHEN** a response includes raw envelopes or private configuration
- **THEN** only normalized public content and media fields SHALL be returned to clients.

### Requirement: Honest platform capabilities
Android Lumina local execution MUST be limited to arm64-v8a and x86_64. ARM32 MUST retain existing sources without a local Lumina fallback. The current iOS application MUST hide Lumina and retain existing anime providers until a separately verified implementation is available.

#### Scenario: Android ARM32 starts the application
- **WHEN** the application runs on armeabi-v7a
- **THEN** Lumina SHALL not be registered as a local provider and existing sources SHALL remain available.

#### Scenario: iOS starts with an existing movie runtime configuration
- **WHEN** the iOS application starts without a separately verified Lumina implementation
- **THEN** Lumina SHALL not be registered or shown and existing anime providers SHALL remain available, even if a movie runtime URL is configured.

### Requirement: Existing home presentation
The application SHALL render SDK data in the existing home components and design tokens without replacing the home structure with an SDK branded panel, and MUST preserve real provider and work identities when opening details.

#### Scenario: Lumina content arrives
- **WHEN** Android or Web receives Lumina home content
- **THEN** existing recommendation cards, carousels and poster rails SHALL render the content and existing history and movie sections SHALL remain available.

### Requirement: Mixed SDK recommendations
The home recommendation board SHALL combine anime SDK recommendations and movie SDK ranking entries with independent loading and failure handling. It MUST NOT claim an unverified seven day measurement window or fabricate a cross-provider popularity score.

#### Scenario: Only one SDK responds
- **WHEN** one SDK finishes while the other is slow or fails
- **THEN** its entries SHALL remain visible and retrying the failed SDK SHALL not erase valid entries.

#### Scenario: Two SDKs share the same numeric video ID
- **WHEN** anime and movie SDK entries have the same ID value
- **THEN** the entries SHALL retain distinct provider identities and open their respective SDK detail pages.

### Requirement: Mixed content types on general feeds
Recommended and popular feeds SHALL combine anime with movie and series content using verified SDK category metadata. Mixing provider labels alone MUST NOT be treated as mixing content types. Anime-only feeds MUST retain their anime-only scope.

#### Scenario: The movie SDK global board only contains anime
- **WHEN** a general feed loads and the movie SDK global board contains only anime
- **THEN** movie and series entries SHALL come from their discovered category catalog or category board rather than relabelling the global entries.

#### Scenario: Movie category data arrives after anime
- **WHEN** anime is already visible and a verified movie or series category finishes later
- **THEN** the general feed SHALL update its featured and recommendation slots to include available non-anime content while retaining real navigation identity.
