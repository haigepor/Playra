## ADDED Requirements

### Requirement: Official and product versions are isolated
Product release automation SHALL accept only Playra release tags and official version references SHALL be identifiable independently of main.

#### Scenario: Official tags are organized
- **WHEN** the confirmed migration is performed
- **THEN** every official tag retains its original object in upstream and a verified backup while product releases use playra/v-prefixed names

### Requirement: Public commits exclude private inputs
Commits SHALL exclude SDK configuration/selftest secrets, device identities, build outputs and pre-existing submodule deletions.

#### Scenario: A clean clone prepares an Android build
- **WHEN** a developer provides the documented local or CI SDK input
- **THEN** the unchanged SDK and required data files are staged and missing inputs produce an explicit build error

### Requirement: Work is verified before push
The implementation SHALL be organized into coherent commits with validation evidence and remote main SHA verification.

#### Scenario: Main is pushed
- **WHEN** the authorized commits pass checks and are pushed
- **THEN** origin/main matches the delivered final commit and no official commit history is rewritten
