package mitm

import "testing"

func TestDiagnosticActivityTracksProcessingAndRelease(t *testing.T) {
	before := DiagnosticActivity()
	func() {
		sessionBudget <- struct{}{}
		defer func() { <-sessionBudget }()
		scriptBudget <- struct{}{}
		defer func() { <-scriptBudget }()
		bodyBudget <- struct{}{}
		defer func() { <-bodyBudget }()
		active := DiagnosticActivity()
		for _, name := range []string{"active-sessions", "active-scripts", "active-bodies"} {
			count := before[name]
			if active[name] != count+1 {
				t.Fatalf("%s count = %d, before = %d", name, active[name], count)
			}
		}
	}()
	for name, count := range DiagnosticActivity() {
		if count != before[name] {
			t.Fatalf("%s did not release: %d", name, count)
		}
	}
}
