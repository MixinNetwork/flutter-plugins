package main

import (
	"testing"
)
import "github.com/stretchr/testify/assert"

func TestLogger(t *testing.T) {
	context := MixinLoggerContext{
		dir:          "./",
		maxFileSize:  1024,
		maxFileCount: 10,
		fileLeading:  "test",
	}
	context._WriteLogToContext("test\n")
	context._WriteLogToContext("test\n")
	context._WriteLogToContext("test\n")
	context._WriteLogToContext("test\n")
	context._WriteLogToContext("test\n")
}

func TestGenerateFileName(t *testing.T) {
	assert.Equal(t, "log_0.log", GenerateFileName(0))
	assert.Equal(t, "log_1.log", GenerateFileName(1))
	assert.Equal(t, "log_2.log", GenerateFileName(2))
	assert.Equal(t, "log_30000.log", GenerateFileName(30000))
}

func TestExtractIndexFromFileName(t *testing.T) {
	index, err := ExtractIndexFromFileName("log_0.log")
	assert.Nil(t, err)
	assert.Equal(t, int64(0), index)

	index, err = ExtractIndexFromFileName("log_1.log")
	assert.Nil(t, err)
	assert.Equal(t, int64(1), index)

	index, err = ExtractIndexFromFileName("log_2.log")
	assert.Nil(t, err)
	assert.Equal(t, int64(2), index)

	index, err = ExtractIndexFromFileName("log_30000.log")
	assert.Nil(t, err)
	assert.Equal(t, int64(30000), index)

	index, err = ExtractIndexFromFileName("edf.log")
	assert.NotNil(t, err)
}
