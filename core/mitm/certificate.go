package mitm

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type Certificate struct {
	PEM         string    `json:"pem"`
	Fingerprint string    `json:"fingerprint"`
	Subject     string    `json:"subject"`
	NotBefore   time.Time `json:"not-before"`
	NotAfter    time.Time `json:"not-after"`
}

type authority struct {
	cert *x509.Certificate
	key  *ecdsa.PrivateKey
	pem  string
}

type certificateFile struct {
	Certificate string `json:"certificate"`
	PrivateKey  string `json:"private-key"`
}

var certificateMu sync.Mutex

func certificatePath(home string) string { return filepath.Join(home, "mitm", "ca-keypair.json") }

func loadAuthority(home string) (*authority, error) {
	data, err := os.ReadFile(certificatePath(home))
	if err != nil {
		return nil, err
	}
	var stored certificateFile
	if err = json.Unmarshal(data, &stored); err != nil {
		return nil, err
	}
	pair, err := tls.X509KeyPair([]byte(stored.Certificate), []byte(stored.PrivateKey))
	if err != nil {
		return nil, err
	}
	cert, err := x509.ParseCertificate(pair.Certificate[0])
	if err != nil {
		return nil, err
	}
	key, ok := pair.PrivateKey.(*ecdsa.PrivateKey)
	if !ok || !cert.IsCA || cert.KeyUsage&x509.KeyUsageCertSign == 0 || time.Now().Before(cert.NotBefore) || time.Now().After(cert.NotAfter) {
		return nil, errors.New("invalid or expired MITM authority")
	}
	return &authority{cert: cert, key: key, pem: stored.Certificate}, nil
}

func describeAuthority(ca *authority) *Certificate {
	digest := sha256.Sum256(ca.cert.Raw)
	parts := make([]string, len(digest))
	for i, b := range digest {
		parts[i] = strings.ToUpper(hex.EncodeToString([]byte{b}))
	}
	return &Certificate{PEM: ca.pem, Fingerprint: strings.Join(parts, ":"), Subject: ca.cert.Subject.CommonName, NotBefore: ca.cert.NotBefore, NotAfter: ca.cert.NotAfter}
}

func GetCertificate(home string) (*Certificate, error) {
	certificateMu.Lock()
	defer certificateMu.Unlock()
	ca, err := loadAuthority(home)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return describeAuthority(ca), nil
}

func serialNumber() (*big.Int, error) {
	return rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
}

func GenerateCertificate(home string) (*Certificate, error) {
	certificateMu.Lock()
	defer certificateMu.Unlock()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	serial, err := serialNumber()
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC()
	template := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: fmt.Sprintf("FlClash CA (%032x)", serial), Organization: []string{"FlClash"}}, NotBefore: now.Add(-time.Hour), NotAfter: now.AddDate(10, 0, 0), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign, MaxPathLenZero: true}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return nil, err
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return nil, err
	}
	stored := certificateFile{Certificate: string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})), PrivateKey: string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER}))}
	data, err := json.Marshal(stored)
	if err != nil {
		return nil, err
	}
	path := certificatePath(home)
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".ca-*")
	if err != nil {
		return nil, err
	}
	defer os.Remove(file.Name())
	if err = file.Chmod(0600); err == nil {
		_, err = file.Write(data)
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return nil, err
	}
	if err = os.Rename(file.Name(), path); err != nil {
		return nil, err
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, err
	}
	return describeAuthority(&authority{cert: cert, key: key, pem: stored.Certificate}), nil
}

func (ca *authority) issue(host string) (*tls.Certificate, error) {
	if host == "" || len(host) > 253 || strings.ContainsAny(host, "/\\\r\n\x00") {
		return nil, fmt.Errorf("invalid certificate host %q", host)
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	serial, err := serialNumber()
	if err != nil {
		return nil, err
	}
	now := time.Now().UTC()
	notAfter := now.Add(30 * 24 * time.Hour)
	if ca.cert.NotAfter.Before(notAfter) {
		notAfter = ca.cert.NotAfter
	}
	template := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: host}, NotBefore: now.Add(-time.Hour), NotAfter: notAfter, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	if ip := net.ParseIP(host); ip != nil {
		template.IPAddresses = []net.IP{ip}
	} else {
		template.DNSNames = []string{host}
	}
	der, err := x509.CreateCertificate(rand.Reader, template, ca.cert, &key.PublicKey, ca.key)
	if err != nil {
		return nil, err
	}
	leaf, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, err
	}
	return &tls.Certificate{Certificate: [][]byte{der, ca.cert.Raw}, PrivateKey: key, Leaf: leaf}, nil
}

func IssueCertificate(home, host string) (string, error) {
	certificateMu.Lock()
	defer certificateMu.Unlock()
	ca, err := loadAuthority(home)
	if err != nil {
		return "", err
	}
	leaf, err := ca.issue(host)
	if err != nil {
		return "", err
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leaf.Certificate[0]})), nil
}
