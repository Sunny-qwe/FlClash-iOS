package mitm

import "testing"

func TestURLRewriteHeaderActionIsAccepted(t *testing.T) {
	rule, err := parseRule("url-rewrite", `^https://api\.example/(.+) https://mock.example/$1 header`)
	if err != nil {
		t.Fatal(err)
	}
	if len(rule.fields) != 3 || rule.fields[2] != "header" {
		t.Fatalf("rule fields = %#v", rule.fields)
	}
}

func TestURLRewriteHeaderActionRejectsRelativeTarget(t *testing.T) {
	if _, err := parseRule("url-rewrite", `^https://api\.example/(.+) /mock/$1 header`); err == nil {
		t.Fatal("relative target accepted")
	}
}

func TestBodyRewriteAcceptsLegacyLoonAction(t *testing.T) {
	rule, err := parseRule("body-rewrite", `^https://api\.example response-body-replace-regex ads replacement text`)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := rule.fields, []string{"http-response", `^https://api\.example`, "ads", "replacement text"}; len(got) != len(want) {
		t.Fatalf("normalized fields = %#v, want %#v", got, want)
	} else {
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("normalized fields = %#v, want %#v", got, want)
			}
		}
	}
}

func TestBinaryBodyModeIsAccepted(t *testing.T) {
	if _, err := parseRule("script", `decode = type=http-response,pattern=^https://api\.example,requires-body=true,binary-body-mode=true,script-path=decode.js`); err != nil {
		t.Fatal(err)
	}
}
