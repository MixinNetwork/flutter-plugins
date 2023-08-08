package main

import "C"

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
)

type MixinLoggerContext struct {
	dir          string
	maxFileSize  int64
	maxFileCount int
	fileLeading  string
	logFile      *os.File
}

var _mixinLoggerContext *MixinLoggerContext

func GenerateFileName(index int64) string {
	return fmt.Sprintf("log_%d.log", index)
}

func ExtractIndexFromFileName(name string) int64 {
	regex, err := regexp.Compile(`log_(\d+).log`)
	if err != nil {
		return -1
	}
	match := regex.FindString(name)
	if match != name {
		return -1
	}
	regex, err = regexp.Compile(`\d+`)
	if err != nil {
		return -1
	}
	indexStr := regex.FindString(match)
	if len(indexStr) == 0 {
		return -1
	}
	index, err := strconv.ParseInt(indexStr, 10, 64)
	if err != nil {
		return -1
	}
	return index
}

type LogFileItem struct {
	index int64
	path  string
}

func (context MixinLoggerContext) _GetLogFileList() ([]LogFileItem, error) {
	files, err := os.ReadDir(context.dir)
	if err != nil {
		return nil, err
	}
	logFiles := make([]LogFileItem, 0)
	for _, file := range files {
		if file.IsDir() {
			continue
		}
		index := ExtractIndexFromFileName(file.Name())
		if index == -1 {
			continue
		}
		logFiles = append(logFiles, LogFileItem{
			index: index,
			path:  filepath.Join(context.dir, file.Name()),
		})
	}
	sort.Slice(logFiles, func(i, j int) bool {
		return logFiles[i].index < logFiles[j].index
	})
	return logFiles, nil
}

func (context MixinLoggerContext) _PrepareLogFile() string {
	info, err := os.Stat(context.dir)
	if os.IsNotExist(err) || !info.IsDir() {
		if err == nil && !info.IsDir() {
			fmt.Println("mixin_logger: log dir is not a directory, try to remove it")
			err = os.Remove(context.dir)
			if err != nil {
				fmt.Println("mixin_logger: remove log dir failed with error: ", err)
				return ""
			}
		}
		err = os.MkdirAll(context.dir, 0755)
		if err != nil {
			fmt.Println("mixin_logger: create log dir failed with error: ", err)
			return ""
		}
	}
	files, err := os.ReadDir(context.dir)
	if err != nil {
		fmt.Println("mixin_logger: read log dir failed with error: ", err)
		return ""
	}
	if len(files) == 0 {
		return GenerateFileName(0)
	}

	logFiles, err := context._GetLogFileList()
	if err != nil {
		fmt.Println("mixin_logger: get log file list failed with error: ", err)
		return ""
	}
	if len(logFiles) == 0 {
		return GenerateFileName(0)
	}

	lastFile := logFiles[len(logFiles)-1]
	file, err := os.OpenFile(lastFile.path, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return ""
	}
	defer func(file *os.File) {
		_ = file.Close()
	}(file)
	stat, err := file.Stat()
	if err != nil {
		return ""
	}
	if stat.Size() < context.maxFileSize {
		return lastFile.path
	}

	newLogFile := GenerateFileName(lastFile.index + 1)
	if len(logFiles) >= context.maxFileCount {
		_ = os.Remove(logFiles[0].path)
	}
	return newLogFile
}

func (context MixinLoggerContext) _WriteLogToContext(str string) {
	fmt.Println(str)
	if context.logFile == nil {
		fileName := context._PrepareLogFile()
		file, err := os.OpenFile(fileName, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
		if err != nil {
			return
		}
		context.logFile = file
	}
	_, _ = context.logFile.WriteString(str)
}

//export MixinLoggerInit
func MixinLoggerInit(
	dir *C.char,
	maxFileSize int64,
	maxFileCount int,
	fileLeading *C.char,
) {
	if _mixinLoggerContext != nil {
		fmt.Println("mixin_logger is already initialized")
		return
	}
	_mixinLoggerContext = &MixinLoggerContext{
		dir:          C.GoString(dir),
		maxFileSize:  maxFileSize,
		maxFileCount: maxFileCount,
		fileLeading:  C.GoString(fileLeading),
	}
}

//export MixinLoggerWriteLog
func MixinLoggerWriteLog(str *C.char) {
	if _mixinLoggerContext == nil {
		fmt.Println("mixin_logger is not initialized")
		return
	}
	_mixinLoggerContext._WriteLogToContext(C.GoString(str))
}

func main() {

}
