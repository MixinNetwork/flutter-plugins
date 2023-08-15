package main

import (
	"fmt"
	"os"
	"path"
	"testing"
)
import "github.com/stretchr/testify/assert"

func TestLogger(t *testing.T) {
	dir := path.Join(os.TempDir(), "mixin_logger_test")
	fmt.Println("test dir:", dir)
	context := MixinLoggerContext{
		dir:          dir,
		maxFileSize:  102400,
		maxFileCount: 10,
		fileLeading:  "test",
	}
	for i := 0; i < 1000000; i++ {
		go context._WriteLogToContext(fmt.Sprintf("test %d", i))
		context.fileLeading = fmt.Sprintf("test_leading_%d", i)
	}
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
