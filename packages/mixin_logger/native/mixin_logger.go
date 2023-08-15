package main

import "C"

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"sync"
)

type MixinLoggerContext struct {
	dir          string
	maxFileSize  int64
	maxFileCount int
	fileLeading  string
	logFile      *os.File
	fileSize     int64
	mu           sync.Mutex
}

var _mixinLoggerContext *MixinLoggerContext

func GenerateFileName(index int64) string {
	return fmt.Sprintf("log_%d.log", index)
}

func ExtractIndexFromFileName(name string) (int64, error) {
	regex, err := regexp.Compile(`log_(\d+).log`)
	if err != nil {
		return 0, err
	}
	match := regex.FindString(name)
	if match != name {
		return 0, fmt.Errorf("mixin_logger: extract index from file name failed")
	}
	regex, err = regexp.Compile(`\d+`)
	if err != nil {
		return 0, err
	}
	indexStr := regex.FindString(match)
	if len(indexStr) == 0 {
		return 0, fmt.Errorf("mixin_logger: extract index from file name failed")
	}
	index, err := strconv.ParseInt(indexStr, 10, 64)
	if err != nil {
		return 0, err
	}
	return index, nil
}

type LogFileItem struct {
	index int64
	path  string
}

func (context *MixinLoggerContext) _GetLogFileList() ([]LogFileItem, error) {
	files, err := os.ReadDir(context.dir)
	if err != nil {
		return nil, err
	}
	logFiles := make([]LogFileItem, 0)
	for _, file := range files {
		if file.IsDir() {
			continue
		}
		index, err := ExtractIndexFromFileName(file.Name())
		if err != nil {
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

func (context *MixinLoggerContext) _PrepareLogFile() (string, error) {
	info, err := os.Stat(context.dir)
	if os.IsNotExist(err) || !info.IsDir() {
		if err == nil && !info.IsDir() {
			err = os.Remove(context.dir)
			if err != nil {
				return "", fmt.Errorf("mixin_logger: remove log dir failed with error: %s", err)
			}
		}
		err = os.MkdirAll(context.dir, 0755)
		if err != nil {
			return "", fmt.Errorf("mixin_logger: create log dir failed with error: %s", err)
		}
	} else if err != nil {
		return "", fmt.Errorf("mixin_logger: stat log dir failed with error: %s", err)
	}
	files, err := os.ReadDir(context.dir)
	if err != nil {
		return "", fmt.Errorf("mixin_logger: read log dir failed with error: %s", err)
	}
	if len(files) == 0 {
		return path.Join(context.dir, GenerateFileName(0)), nil
	}

	logFiles, err := context._GetLogFileList()
	if err != nil {
		return "", fmt.Errorf("mixin_logger: get log file list failed with error: %s", err)
	}
	if len(logFiles) == 0 {
		return path.Join(context.dir, GenerateFileName(0)), nil
	}

	lastFile := logFiles[len(logFiles)-1]
	file, err := os.OpenFile(lastFile.path, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
	if err != nil {
		return "", fmt.Errorf("mixin_logger: open log file failed with error: %s", err)
	}
	defer func(file *os.File) {
		_ = file.Close()
	}(file)
	stat, err := file.Stat()
	if err != nil {
		return "", fmt.Errorf("mixin_logger: get log file stat failed with error: %s", err)
	}
	if stat.Size() < context.maxFileSize {
		return lastFile.path, nil
	}

	newLogFile := GenerateFileName(lastFile.index + 1)
	if len(logFiles) >= context.maxFileCount {
		_ = os.Remove(logFiles[0].path)
	}
	return path.Join(context.dir, newLogFile), nil
}

func writeLine(file *os.File, str string) (int64, error) {
	fileSize := int64(0)
	write, err := file.WriteString(str)
	if err != nil {
		return 0, err
	}
	fileSize += int64(write)
	write, err = file.Write([]byte{'\n'})
	if err != nil {
		return 0, err
	}
	fileSize += int64(write)
	return fileSize, nil
}

func (context *MixinLoggerContext) _WriteLogToContext(str string) {
	context.mu.Lock()
	defer context.mu.Unlock()
	if context.logFile == nil {
		filePath, err := context._PrepareLogFile()
		if err != nil {
			fmt.Println("mixin_logger: write log failed with error: ", err)
			return
		}
		file, err := os.OpenFile(filePath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
		if err != nil {
			fmt.Println("mixin_logger: open log file failed with error: ", err)
			return
		}
		info, err := file.Stat()
		if err != nil {
			fmt.Println("mixin_logger: get log file stat failed with error: ", err)
			return
		}
		context.fileSize = info.Size()
		context.logFile = file

		write, _ := writeLine(file, context.fileLeading)
		context.fileSize += write

	}
	write, err := writeLine(context.logFile, str)
	context.fileSize += write

	if context.fileSize >= context.maxFileSize && context.logFile != nil {
		err = context.logFile.Close()
		if err != nil {
			fmt.Println("mixin_logger: close log file failed with error: ", err)
			return
		}
		context.logFile = nil
		context.fileSize = 0
	}

	if err != nil {
		fmt.Println("mixin_logger: write log failed with error: ", err)
		return
	}
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

//export MixinLoggerSetFileLeading
func MixinLoggerSetFileLeading(str *C.char) {
	if _mixinLoggerContext == nil {
		fmt.Println("mixin_logger is not initialized")
		return
	}
	_mixinLoggerContext.fileLeading = C.GoString(str)
}

func main() {

}
