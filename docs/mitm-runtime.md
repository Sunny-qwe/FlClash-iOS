# MITM runtime in this iOS fork

The wrapper implements interception using Go's TLS and HTTP servers. Mihomo still
routes every outbound connection, including script network requests. The narrow
TCP/UDP hooks in `core/Clash.Meta/tunnel/interceptor.go` are a new feature boundary;
ordinary connections continue through the original tunnel path. Reload validation
happens before the active engine is replaced.

## Implemented

- Newly generated ECDSA root keys and signed domain/IP leaf certificates, with
  fingerprints and dates derived from the certificates themselves.
- System-anchor trust verification on iOS and export of an unsigned root-certificate
  `.mobileconfig`. The user installs the profile and enables full trust in Settings.
- First-match hostname allowlists/exclusions. TLS interception is gated by trust
  state or the explicit decrypt-untrusted setting. QUIC blocking applies only to
  listed hostnames while TLS interception is active.
- HTTP/1.1 and optional HTTP/2; URL rejection/redirects, header/body replacement,
  map-local responses, bounded gzip/deflate/Brotli decoding and WebSocket passthrough.
- Goja request/response and manually run generic scripts: `$request`, `$response`,
  `$done`, `$argument`, `$httpClient`, `$task.fetch`, bounded one-shot timers,
  `$persistentStore`/`$prefs`, console logs, base64 helpers. Notifications are logged.
- Capture lists, headers, bodies, actions and errors; a separate list makes captures
  accessible independently of an outbound connection's tracker lifetime.
- Compatible module routing rules apply even when HTTPS decryption is disabled.
  Invalid HTTP-only predicates are never inserted as mihomo logical routing rules.

## Limits and remaining compatibility

This is partial compatibility with Surge, Loon and Quantumult X module formats,
not their proprietary engines. Cron/event scheduling, binary-body/full-header script
modes, arbitrary script libraries and platform-specific APIs are unsupported.
Validation identifies unsupported rules, and script errors preserve the original
request or response rather than taking down the VPN.

For the iOS extension, at most 16 intercepted connections, four HTTP/2 streams per
connection, one script, 32 cached leaf certificates, 256 KiB processed bodies and
1 MiB/64 capture entries are kept. Each script has a 500 ms default timeout and a
2 second maximum, at most four network calls and bounded timer runs. Goja has no
per-runtime hard heap limit; script consent remains necessary and these bounds do
not prove every third-party script can run within iOS's process memory allowance.
Oversized bodies retain their original bytes. Request bodies with content encodings
and unknown response encodings are passed through. Certificate-pinned apps may reject
interception and should be excluded from the hostname list.

## References

Architectural research used the public go-mitmproxy project:
https://github.com/lqqyt2423/go-mitmproxy

JavaScript execution uses Goja, pinned by commit in `core/go.mod`:
https://github.com/dop251/goja

The certificate, routing hook and HTTP integration here are original implementation;
no proprietary QX/Surge code or private upstream MITM branch is included.

## Verification

`go test . ./mitm` and `go test -tags=with_low_memory . ./mitm` cover real TLS
requests, root renewal/leaf verification, response scripts, script network APIs,
persistent storage, timer/loop interruption, compressed bodies, oversized-body byte
preservation, routing rejection, failed-config preservation and packaged GeoSite loading.
The iOS workflow also runs the module parser, trust-store and module UI suites before
building. Compilation and automated tests do not replace phone testing after signing.
