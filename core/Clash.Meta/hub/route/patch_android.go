//go:build android || ios

package route

func init() {
	SetEmbedMode(true) // set embed mode default
}
