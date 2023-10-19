#include "mixin_logger.h"

#include <iostream>
#include <fstream>
#include <mutex>
#include <filesystem>
#include <regex>
#include <utility>

namespace mixin_logger {

    namespace fs = std::filesystem;

    struct LogFileItem {
        int64_t index;
        fs::path file;
    };

    int ExtractIndexFromFileName(const std::string &name, int64_t &index) {
        std::regex pattern("log_(\\d+)\\.log");
        std::smatch match;

        if (std::regex_search(name, match, pattern)) {
            if (match.size() > 1) {
                std::string indexStr = match[1].str();
                try {
                    index = std::stoll(indexStr);
                    return 0;  // Success
                } catch (const std::invalid_argument &ia) {
                    return -1; // Parsing error
                } catch (const std::out_of_range &oor) {
                    return -2; // Out of range
                }
            }
        }

        return -3; // No match found
    }


    std::string GenerateFileName(int64_t index) {
        std::string file_name;
        file_name.append("log_");
        file_name.append(std::to_string(index));
        file_name.append(".log");
        return file_name;
    }

    u_int64_t WriteLine(std::ofstream *file, const std::string &line) {
        *file << line;
        *file << std::endl;
        return line.size() + sizeof('\n');
    }


    class LoggerContext {
    private:
        std::string dir_;
        intptr_t max_file_size_;
        intptr_t max_file_count_;
        std::string file_leading_;
        std::ofstream *file_;
        int64_t file_size_;
        std::mutex mutex_;


        std::vector<LogFileItem> GetLogFileList() {
            std::vector<LogFileItem> logFiles;
            fs::path dirPath(dir_);

            if (!fs::is_directory(dirPath)) {
                fs::remove(dirPath);
            }
            if (!fs::exists(dirPath)) {
                fs::create_directories(dirPath);
            }
            for (const auto &entry: fs::directory_iterator(dirPath)) {
                if (entry.is_regular_file()) {
                    long long index;
                    std::string fileName = entry.path().filename().string();
                    if (ExtractIndexFromFileName(fileName, index)) {
                        logFiles.push_back({index, entry.path()});
                    }
                }
            }

            std::sort(logFiles.begin(), logFiles.end(), [](const LogFileItem &a, const LogFileItem &b) {
                return a.index < b.index;
            });

            return logFiles;
        }


        fs::path PrepareLogFile() {
            std::vector<LogFileItem> files = GetLogFileList();
            if (files.empty()) {
                return fs::path(dir_) / GenerateFileName(0);
            }

            auto last_file = files.back();

            fs::file_status status = fs::status(last_file.file);

            if (fs::file_size(last_file.file) < max_file_size_) {
                return last_file.file;
            }

            auto new_log_file = fs::path(dir_) / GenerateFileName(last_file.index + 1);

            if (files.size() >= max_file_count_) {
                fs::remove(files.front().file);
            }

            return new_log_file;
        }

    public:
        LoggerContext(
                std::string dir,
                intptr_t maxFileSize, intptr_t maxFileCount,
                std::string fileLeading
        ) : dir_(std::move(dir)),
            max_file_size_(maxFileSize),
            max_file_count_(maxFileCount),
            file_leading_(std::move(fileLeading)),
            file_(nullptr), file_size_(0),
            mutex_() {

        }

        ~LoggerContext() = default;

        void SetFileLeading(const std::string &file_leading) {
            file_leading_ = file_leading;
        }

        void WriteLog(const std::string &log) {
            auto lock = std::lock_guard<std::mutex>(mutex_);
            if (file_ == nullptr) {
                auto log_file = PrepareLogFile();
                file_ = new std::ofstream(log_file);

                if (!fs::exists(log_file)) {
                    file_size_ = 0;
                } else {
                    file_size_ = int64_t(fs::file_size(log_file));
                }
            }
            auto write = WriteLine(file_, log);
            file_size_ += int64_t(write);

            if (file_size_ >= max_file_size_) {
                file_->close();
                delete file_;
                file_ = nullptr;
                file_size_ = 0;
            }
        }

    };

    LoggerContext *loggerContext = nullptr;

}

FFI_PLUGIN_EXPORT intptr_t
mixin_logger_init(
        const char *dir, intptr_t max_file_size,
        intptr_t max_file_count, const char *file_leading) {
    if (mixin_logger::loggerContext != nullptr) {
        return -1;
    }
    mixin_logger::loggerContext = new mixin_logger::LoggerContext(
            std::string(dir), max_file_size,
            max_file_count, std::string(file_leading)
    );
    return 0;
}

FFI_PLUGIN_EXPORT intptr_t mixin_logger_set_file_leading(const char *file_leading) {
    if (mixin_logger::loggerContext == nullptr) {
        return -1;
    }
    mixin_logger::loggerContext->SetFileLeading(std::string(file_leading));
}

FFI_PLUGIN_EXPORT intptr_t mixin_logger_write_log(const char *log) {
    if (mixin_logger::loggerContext == nullptr) {
        return -1;
    }
    mixin_logger::loggerContext->WriteLog(std::string(log));
}
