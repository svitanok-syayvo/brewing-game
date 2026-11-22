class_name Config
extends RefCounted
## Build-time switches for playtests. They are design toggles, not Data Sheet values,
## so they live here in one place (FIRST_PLAYABLE §9).

## GDD 11.1 (TBD) and decision D6: does an Ingredient's tooltip also reveal the effect of
## its other Form? Off by default, so playtest question 11.3 Q3 ("experimentation or
## guessing?") tests the hidden version. Set to true to test the other version.
const SHOW_SHIFTED_IN_TOOLTIP := false
