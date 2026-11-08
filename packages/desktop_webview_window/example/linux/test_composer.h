#ifndef RUNNER_TEST_COMPOSER_H_
#define RUNNER_TEST_COMPOSER_H_

#include <flutter_linux/flutter_linux.h>

// An example native composer. "sidebar" stacks the controls left of the page;
// "close:<callback>" closes the browser from that callback for the
// integration suite. Other browsers use the plugin's default composer.
void test_composer_install();

// Answers the integration suite on "webview_example/native_test".
void test_composer_register_channel(FlBinaryMessenger* messenger);

#endif  // RUNNER_TEST_COMPOSER_H_
