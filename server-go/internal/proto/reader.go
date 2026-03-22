package proto

import (
	"encoding/binary"
	"errors"
)

// ErrUnderflow is returned when a Reader runs out of data.
var ErrUnderflow = errors.New("proto: packet underflow")

// Reader reads fields from a binary payload in Era Online big-endian format.
type Reader struct {
	buf []byte
	pos int
}

// NewReader wraps a payload slice.
func NewReader(data []byte) *Reader {
	return &Reader{buf: data}
}

func (r *Reader) need(n int) error {
	if r.pos+n > len(r.buf) {
		return ErrUnderflow
	}
	return nil
}

func (r *Reader) ReadU8() (uint8, error) {
	if err := r.need(1); err != nil {
		return 0, err
	}
	v := r.buf[r.pos]
	r.pos++
	return v, nil
}

func (r *Reader) ReadU16() (uint16, error) {
	if err := r.need(2); err != nil {
		return 0, err
	}
	v := binary.BigEndian.Uint16(r.buf[r.pos:])
	r.pos += 2
	return v, nil
}

func (r *Reader) ReadU32() (uint32, error) {
	if err := r.need(4); err != nil {
		return 0, err
	}
	v := binary.BigEndian.Uint32(r.buf[r.pos:])
	r.pos += 4
	return v, nil
}

func (r *Reader) ReadI8() (int8, error) {
	v, err := r.ReadU8()
	return int8(v), err
}

func (r *Reader) ReadI16() (int16, error) {
	v, err := r.ReadU16()
	return int16(v), err
}

func (r *Reader) ReadI32() (int32, error) {
	v, err := r.ReadU32()
	return int32(v), err
}

func (r *Reader) ReadI64() (int64, error) {
	hi, err := r.ReadU32()
	if err != nil {
		return 0, err
	}
	lo, err := r.ReadU32()
	if err != nil {
		return 0, err
	}
	return (int64(hi) << 32) | int64(lo), nil
}

// ReadStr reads a u16-length-prefixed UTF-8 string.
func (r *Reader) ReadStr() (string, error) {
	n, err := r.ReadU16()
	if err != nil {
		return "", err
	}
	if err := r.need(int(n)); err != nil {
		return "", err
	}
	s := string(r.buf[r.pos : r.pos+int(n)])
	r.pos += int(n)
	return s, nil
}

// ReadBytes reads exactly n raw bytes.
func (r *Reader) ReadBytes(n int) ([]byte, error) {
	if err := r.need(n); err != nil {
		return nil, err
	}
	b := make([]byte, n)
	copy(b, r.buf[r.pos:r.pos+n])
	r.pos += n
	return b, nil
}

// Remaining returns the number of unread bytes.
func (r *Reader) Remaining() int { return len(r.buf) - r.pos }
