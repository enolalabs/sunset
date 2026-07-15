package version

import (
	"runtime/debug"
	"strings"
)

// BuildVersion is injected at release build time via ldflags:
//
//	-X github.com/enolalabs/sunset/internal/version.BuildVersion=1.0.1
//
// Empty means "not set"; the resolver then falls back to runtime build info.
var BuildVersion string

// Current returns the resolved sunset version string.
//
// Precedence:
//  1. BuildVersion (when non-empty) — set by release ldflags.
//  2. debug.ReadBuildInfo().Main.Version — embedded by `go build`.
//  3. "dev" — local, untagged, or otherwise unidentified builds.
//
// A single leading "v" is stripped from the chosen value so that
// "v1.0.1" is reported as "1.0.1".
func Current() string {
	var mainVersion string
	if info, ok := debug.ReadBuildInfo(); ok {
		mainVersion = info.Main.Version
	}
	return resolve(BuildVersion, mainVersion)
}

// resolve applies the version precedence and normalization.
//
//	- A non-empty buildVersion always wins.
//	- Otherwise mainVersion is used unless it is empty or "(devel)".
//	- Anything else resolves to "dev".
//
// Exactly one leading "v" is stripped from the selected value.
func resolve(buildVersion, mainVersion string) string {
	switch {
	case buildVersion != "":
		return stripOneLeadingV(buildVersion)
	case mainVersion != "" && mainVersion != "(devel)":
		return stripOneLeadingV(mainVersion)
	default:
		return "dev"
	}
}

// stripOneLeadingV removes a single leading "v" (lowercase only) so that
// "v1.0.1" → "1.0.1" but "vv1.0.1" → "v1.0.1" and "1.0.1" → "1.0.1".
func stripOneLeadingV(s string) string {
	return strings.TrimPrefix(s, "v")
}
