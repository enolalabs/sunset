package version

import "testing"

func TestResolve(t *testing.T) {
	cases := []struct {
		name        string
		build       string
		mainVersion string
		want        string
	}{
		{
			name:        "non-empty build override wins",
			build:       "1.0.1",
			mainVersion: "v2.5.0",
			want:        "1.0.1",
		},
		{
			name:        "build override strips one leading v",
			build:       "v1.2.3",
			mainVersion: "v9.9.9",
			want:        "1.2.3",
		},
		{
			name:        "build override strips only one leading v",
			build:       "vv1.0.1",
			mainVersion: "",
			want:        "v1.0.1",
		},
		{
			name:        "build info v1.0.1 normalizes to 1.0.1",
			build:       "",
			mainVersion: "v1.0.1",
			want:        "1.0.1",
		},
		{
			name:        "build info without leading v unchanged",
			build:       "",
			mainVersion: "1.0.1",
			want:        "1.0.1",
		},
		{
			name:        "devel main version resolves to dev",
			build:       "",
			mainVersion: "(devel)",
			want:        "dev",
		},
		{
			name:        "missing build info (empty main version) resolves to dev",
			build:       "",
			mainVersion: "",
			want:        "dev",
		},
		{
			name:        "empty build override falls through to main version",
			build:       "",
			mainVersion: "v3.0.0",
			want:        "3.0.0",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := resolve(tc.build, tc.mainVersion); got != tc.want {
				t.Errorf("resolve(%q, %q) = %q, want %q",
					tc.build, tc.mainVersion, got, tc.want)
			}
		})
	}
}

func TestCurrent_DefaultsToDevInTestBuild(t *testing.T) {
	got := Current()
	if got == "" {
		t.Error("Current() should never return empty string")
	}
}
