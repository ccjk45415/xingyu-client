#pragma once
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> RegisterSystemProxy(flutter::BinaryMessenger* messenger);
