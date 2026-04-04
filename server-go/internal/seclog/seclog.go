// Package seclog writes structured security events in logfmt format to a dedicated file.
// Events are written one per line with fixed field order, suitable for CrowdSec parsing.
//
// Format: ts=<RFC3339> event=<name> ip=<addr> listen_port=<port> [field=value ...]
package seclog

import (
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

// Logger writes security events to a file in logfmt format.
// A nil Logger is safe to use — all writes are no-ops.
type Logger struct {
	mu sync.Mutex
	w  io.WriteCloser
}

// New opens or creates the security log at path.
// Returns a no-op logger if path is empty.
func New(path string) (*Logger, error) {
	if path == "" {
		return &Logger{}, nil
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0640)
	if err != nil {
		return nil, fmt.Errorf("seclog: open %s: %w", path, err)
	}
	return &Logger{w: f}, nil
}

// Log emits one security event line.
// kv should be alternating key, value pairs (key must be a string).
func (l *Logger) Log(event string, kv ...any) {
	if l == nil || l.w == nil {
		return
	}
	var sb strings.Builder
	sb.WriteString("ts=")
	sb.WriteString(time.Now().UTC().Format(time.RFC3339))
	sb.WriteString(" event=")
	sb.WriteString(event)
	for i := 0; i+1 < len(kv); i += 2 {
		key := fmt.Sprintf("%v", kv[i])
		val := fmt.Sprintf("%v", kv[i+1])
		sb.WriteByte(' ')
		sb.WriteString(key)
		sb.WriteByte('=')
		if needsQuote(val) {
			fmt.Fprintf(&sb, "%q", val)
		} else {
			sb.WriteString(val)
		}
	}
	sb.WriteByte('\n')

	l.mu.Lock()
	_, _ = io.WriteString(l.w, sb.String())
	l.mu.Unlock()
}

// Close closes the underlying log file.
func (l *Logger) Close() error {
	if l == nil || l.w == nil {
		return nil
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.w.Close()
}

// ExtractIP returns only the IP portion of a "host:port" address string.
func ExtractIP(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return host
}

// ExtractPort returns only the port portion of a "host:port" address string.
func ExtractPort(addr string) string {
	_, port, err := net.SplitHostPort(addr)
	if err != nil {
		return ""
	}
	return port
}

func needsQuote(s string) bool {
	if s == "" {
		return true
	}
	for _, c := range s {
		if c == ' ' || c == '"' || c == '=' || c == '\n' || c == '\r' || c == '\\' {
			return true
		}
	}
	return false
}
