package proto

import "encoding/binary"

// Writer builds a binary payload in Era Online big-endian format.
type Writer struct {
	buf []byte
}

// NewWriter returns a new Writer with preallocated capacity.
func NewWriter(cap int) *Writer {
	return &Writer{buf: make([]byte, 0, cap)}
}

func (w *Writer) WriteU8(v uint8) {
	w.buf = append(w.buf, v)
}

func (w *Writer) WriteU16(v uint16) {
	w.buf = append(w.buf, byte(v>>8), byte(v))
}

func (w *Writer) WriteU32(v uint32) {
	var b [4]byte
	binary.BigEndian.PutUint32(b[:], v)
	w.buf = append(w.buf, b[:]...)
}

func (w *Writer) WriteI8(v int8)   { w.WriteU8(uint8(v)) }
func (w *Writer) WriteI16(v int16) { w.WriteU16(uint16(v)) }
func (w *Writer) WriteI32(v int32) { w.WriteU32(uint32(v)) }

func (w *Writer) WriteI64(v int64) {
	w.WriteU32(uint32(v >> 32))
	w.WriteU32(uint32(v))
}

// WriteStr writes a length-prefixed UTF-8 string (u16 length + bytes).
func (w *Writer) WriteStr(s string) {
	b := []byte(s)
	w.WriteU16(uint16(len(b)))
	w.buf = append(w.buf, b...)
}

// WriteBytes appends raw bytes.
func (w *Writer) WriteBytes(b []byte) {
	w.buf = append(w.buf, b...)
}

// Bytes returns the accumulated payload bytes.
func (w *Writer) Bytes() []byte { return w.buf }

// Len returns the current payload length.
func (w *Writer) Len() int { return len(w.buf) }
