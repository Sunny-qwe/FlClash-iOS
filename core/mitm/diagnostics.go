package mitm

func DiagnosticActivity() map[string]int {
	return map[string]int{
		"active-sessions": len(sessionBudget),
		"active-scripts":  len(scriptBudget),
		"active-bodies":   len(bodyBudget),
	}
}
