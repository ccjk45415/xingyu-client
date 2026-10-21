#ifndef RUNNER_SECURE_STORAGE_H_
#define RUNNER_SECURE_STORAGE_H_
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterSecureStorage(flutter::BinaryMessenger* messenger);
#endif
