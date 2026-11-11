package core

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/constant"
)

func TestInitResolvesPackagedGeoDataNames(t *testing.T) {
	previousHome := constant.Path.HomeDir()
	previousSite, previousIP := constant.GeositeName, constant.GeoipName
	previousInit := isInit.Load()
	previousSDK := sdkVersion.Load()
	t.Cleanup(func() {
		constant.SetHomeDir(previousHome)
		constant.GeositeName, constant.GeoipName = previousSite, previousIP
		isInit.Store(previousInit)
		sdkVersion.Store(previousSDK)
	})
	for _, names := range [][2]string{{"GEOSITE.dat", "GEOIP.dat"}, {"GeoSite.dat", "GeoIP.dat"}} {
		t.Run(names[0], func(t *testing.T) {
			home := t.TempDir()
			for _, name := range names {
				if err := os.WriteFile(filepath.Join(home, name), []byte{1}, 0600); err != nil {
					t.Fatal(err)
				}
			}
			if err := handleInit(&InitParams{HomeDir: home}); err != nil {
				t.Fatal(err)
			}
			if constant.GeositeName != names[0] || constant.GeoipName != names[1] {
				t.Fatalf("geo names = %s/%s, want %s/%s", constant.GeositeName, constant.GeoipName, names[0], names[1])
			}
		})
	}
}

func TestPackagedGeoSiteLoadsDNSFallbackCategory(t *testing.T) {
	previousHome := constant.Path.HomeDir()
	previousSite := constant.GeositeName
	t.Cleanup(func() { constant.SetHomeDir(previousHome); constant.GeositeName = previousSite })
	home := t.TempDir()
	data, err := os.ReadFile(filepath.Join("..", "assets", "data", "GEOSITE.dat"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "GEOSITE.dat"), data, 0600); err != nil {
		t.Fatal(err)
	}
	constant.SetHomeDir(home)
	constant.GeositeName = "GeoSite.dat"
	constant.Path.GeoSite()
	loader, err := geodata.GetGeoDataLoader("memconservative")
	if err != nil {
		t.Fatal(err)
	}
	domains, err := loader.LoadGeoSite("gfw")
	if err != nil || len(domains) == 0 {
		t.Fatalf("DNS fallback GeoSite gfw: %d entries, %v", len(domains), err)
	}
}
