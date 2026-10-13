## ADDED Requirements

### Requirement: Three adaptive episode card layouts
Inline and sheet episode lists SHALL share the same text measurement rule and preserve original episode order and identity. Short labels of at most eight Unicode code points fitting compact cells SHALL use compact columns. Longer labels fitting half of the available width SHALL use two-column rows. Labels exceeding half-row text capacity SHALL use full-width cards with at most two text lines. Font scale, padding and the playing mark SHALL be included in measurement.
#### Scenario: Dated variety episodes
- **WHEN** labels such as 20260404上 exceed compact capacity but fit half-row capacity
- **THEN** two cards share a row in both the inline list and the sheet.
#### Scenario: Very long title
- **WHEN** the label exceeds half-row capacity
- **THEN** one card fills the row, shows at most two lines, and preserves the full original label for accessibility.

### Requirement: Smooth segmented selector
Episode range tabs SHALL use one moving indicator with 240ms animation, preserve labels and real episode numbers under descending order, and disable the animation when reduced motion is enabled.
#### Scenario: Select another range then play
- **WHEN** a user changes range and selects a nonconsecutive-number episode
- **THEN** the actual episodeNum and code are passed to playback rather than the range index or display position.
