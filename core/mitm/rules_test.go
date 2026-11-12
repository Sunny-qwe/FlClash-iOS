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
