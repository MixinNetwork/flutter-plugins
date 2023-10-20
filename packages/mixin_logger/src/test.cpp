
#include "gtest/gtest.h"
#include "mixin_logger.cpp"


using namespace mixin_logger;

TEST(ExtractIndexFromFileName, Extract) {
    int64_t index;
    int ret = ExtractIndexFromFileName("log_0.log", index);
    EXPECT_EQ(ret, true);
    EXPECT_EQ(index, 0);

    ret = ExtractIndexFromFileName("log_1.log", index);
    EXPECT_EQ(ret, true);
    EXPECT_EQ(index, 1);

    ret = ExtractIndexFromFileName("log_2.log", index);
    EXPECT_EQ(ret, true);
    EXPECT_EQ(index, 2);

    ret = ExtractIndexFromFileName("log_30000.log", index);
    EXPECT_EQ(ret, true);
    EXPECT_EQ(index, 30000);

    ret = ExtractIndexFromFileName("log_test.log", index);
    EXPECT_EQ(ret, false);

}


TEST(GenerateFileName, TEST) {
    std::string file_name = GenerateFileName(0);
    EXPECT_EQ(file_name, "log_0.log");

    file_name = GenerateFileName(1);
    EXPECT_EQ(file_name, "log_1.log");

    file_name = GenerateFileName(2);
    EXPECT_EQ(file_name, "log_2.log");

    file_name = GenerateFileName(30000);
    EXPECT_EQ(file_name, "log_30000.log");
}

TEST(WriteLine, TEST) {
    std::ofstream file;
    file.open("test.log", std::ios::out | std::ios::app);
    auto size = WriteLine(&file, "test");
    EXPECT_EQ(size, 5);
    file.close();
    std::remove("test.log");
}

TEST(LoggerContext, WriteLog) {
    auto dir = std::filesystem::temp_directory_path() / "mixin_logger_test";
    std::filesystem::create_directories(dir);
    std::cout << "test dir: " << dir << std::endl;

    // clean files
    for (auto &p: std::filesystem::directory_iterator(dir)) {
        std::cout << "remove file: " << p.path() << std::endl;
        std::filesystem::remove(p.path());
    }

    LoggerContext context(dir.string(), 1024, 3, "this is a file leading...");
    for (int i = 0; i < 100; ++i) {
        context.WriteLog("this is a test log: " + std::to_string(i));
    }

    // check files
    std::vector<std::filesystem::path> files;
    for (auto &p: std::filesystem::directory_iterator(dir)) {
        files.push_back(p.path());
    }

    std::vector<std::string> filenames = {"log_0.log", "log_1.log", "log_2.log"};
    EXPECT_EQ(files.size(), filenames.size());
    for (const auto &file: files) {
        EXPECT_TRUE(std::count(filenames.begin(), filenames.end(), file.filename()) > 0);
    }

    auto log_index = 0;

    for (int i = 0; i < 3; i++) {
        std::ifstream file(dir / filenames[i]);
        std::string line;
        std::getline(file, line);
        EXPECT_EQ(line, "this is a file leading...");
        while (std::getline(file, line)) {
            std::cout << line << std::endl;
            EXPECT_EQ(line, "this is a test log: " + std::to_string(log_index));
            log_index++;
        }
        file.close();
    }

    EXPECT_EQ(log_index, 100);

}

TEST(LoggerContext, AppendLog) {
    auto dir = std::filesystem::temp_directory_path() / "mixin_logger_test";
    std::filesystem::create_directories(dir);
    std::cout << "test dir: " << dir << std::endl;

    // clean files
    for (auto &p: std::filesystem::directory_iterator(dir)) {
        std::cout << "remove file: " << p.path() << std::endl;
        std::filesystem::remove(p.path());
    }

    std::vector<std::string> old_last_log_content;
    {
        LoggerContext context(dir.string(), 1024, 3, "this is a file leading...");
        for (int i = 0; i < 100; ++i) {
            context.WriteLog("this is a test log: " + std::to_string(i));
        }
        // record the last file content
        std::ifstream file(dir / "log_2.log");
        std::string line;
        while (std::getline(file, line)) {
            old_last_log_content.push_back(line);
        }
    }

    LoggerContext context(dir.string(), 1024, 3, "this is a new file leading...");
    for (int i = 0; i < 100; ++i) {
        context.WriteLog("this is a new test log: " + std::to_string(i));
    }

    // check files
    std::vector<std::filesystem::path> files;
    for (auto &p: std::filesystem::directory_iterator(dir)) {
        files.push_back(p.path());
    }

    std::vector<std::string> filenames = {"log_2.log", "log_3.log", "log_4.log"};
    EXPECT_EQ(files.size(), filenames.size());
    for (const auto &file: files) {
        EXPECT_TRUE(std::count(filenames.begin(), filenames.end(), file.filename()) > 0);
    }

    auto log_index = 0;

    // check log_2.log, should mix with old log
    {
        std::ifstream file(dir / filenames[0]);
        std::string line;
        for (const auto &old_line: old_last_log_content) {
            std::cout << line << std::endl;
            std::getline(file, line);
            EXPECT_EQ(line, old_line);
        }

        // start with new log
        while (std::getline(file, line)) {
            std::cout << line << std::endl;
            EXPECT_EQ(line, "this is a new test log: " + std::to_string(log_index));
            log_index++;
        }
        file.close();
    }

    // check log_3.log log_4.log
    for (int i = 1; i < filenames.size(); i++) {
        std::ifstream file(dir / filenames[i]);
        std::string line;
        std::getline(file, line);
        EXPECT_EQ(line, "this is a new file leading...");
        while (std::getline(file, line)) {
            std::cout << line << std::endl;
            EXPECT_EQ(line, "this is a new test log: " + std::to_string(log_index));
            log_index++;
        }
        file.close();
    }

    EXPECT_EQ(log_index, 100);

}