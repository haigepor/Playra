## ADDED Requirements

### Requirement: Playra user-facing identity
The application SHALL use Playra for user-facing names and update metadata while preserving installation and storage compatibility identifiers.

#### Scenario: Existing Android installation is updated
- **WHEN** a user installs the renamed build over the current test app
- **THEN** the launcher and application show Playra and existing identity/history/settings remain available

### Requirement: Production developer tools are hidden
Production builds SHALL hide diagnostic and component laboratory entries and SHALL prevent direct navigation to their routes unless an explicit diagnostics build flag is enabled.

#### Scenario: Production profile and settings are opened
- **WHEN** the application is built without diagnostics enabled
- **THEN** error logs and the component laboratory are absent from both menus and route registration

### Requirement: Product-focused about page
The about page SHALL display Playra, current version, help/privacy information and secondary license/credits access without source-code or upstream promotional entries.

#### Scenario: About is opened on a narrow device
- **WHEN** a user opens about with enlarged text on a 320px viewport
- **THEN** the content remains readable without overflow and update actions expose loading and retry behavior
