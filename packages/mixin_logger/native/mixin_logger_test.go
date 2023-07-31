package main

import "testing"
import "github.com/stretchr/testify/assert"

func TestLogger(t *testing.T) {
	MixinLoggerInit("./", 1024, 10, "test")
	MixinLoggerWriteLog("test\n")
	MixinLoggerWriteLog("test\n")
	MixinLoggerWriteLog("test\n")
	MixinLoggerWriteLog("test\n")
	MixinLoggerWriteLog("test\n")
	MixinLoggerWriteLog("test\n")
}

func TestGenerateFileName(t *testing.T) {
	assert.Equal(t, "log_0.log", GenerateFileName(0))
	assert.Equal(t, "log_1.log", GenerateFileName(1))
	assert.Equal(t, "log_2.log", GenerateFileName(2))
	assert.Equal(t, "log_30000.log", GenerateFileName(30000))
}

func TestExtractIndexFromFileName(t *testing.T) {
	assert.Equal(t, int64(0), ExtractIndexFromFileName("log_0.log"))
	assert.Equal(t, int64(1), ExtractIndexFromFileName("log_1.log"))
	assert.Equal(t, int64(2), ExtractIndexFromFileName("log_2.log"))
	assert.Equal(t, int64(30000), ExtractIndexFromFileName("log_30000.log"))
	assert.Equal(t, int64(-1), ExtractIndexFromFileName("edf.log"))
}
