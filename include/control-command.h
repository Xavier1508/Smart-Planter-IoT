#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

namespace planter {

constexpr size_t kControlLineCapacity = 96;

struct ControlCommand {
  bool valid = false;
  bool pumpSet = false;
  bool pumpOn = false;
  bool pumpAuto = false;
  bool lightSet = false;
  bool lightOn = false;
  bool lightAuto = false;
  uint32_t durationSeconds = 5;
  unsigned long id = 0;
  bool hasId = false;
};

// One bounded, whitespace-separated command line:
//   CTRL pump=on dur=5 id=12
//   CTRL pump=off id=13
//   CTRL pump=auto
//   CTRL light=on id=14
//   CTRL light=auto
// Unknown keys, malformed values or an empty command are rejected.
inline ControlCommand parseControlLine(const char* line) {
  ControlCommand command;
  if (line == nullptr) return command;
  const size_t length = strlen(line);
  if (length == 0 || length >= kControlLineCapacity) return command;
  char buffer[kControlLineCapacity];
  memcpy(buffer, line, length + 1);

  char* save = nullptr;
  char* token = strtok_r(buffer, " ", &save);
  if (token == nullptr || strcmp(token, "CTRL") != 0) return command;
  while ((token = strtok_r(nullptr, " ", &save)) != nullptr) {
    char* separator = strchr(token, '=');
    if (separator == nullptr) return command;
    *separator = '\0';
    const char* key = token;
    const char* value = separator + 1;
    if (strcmp(key, "pump") == 0) {
      command.pumpSet = true;
      if (strcmp(value, "on") == 0) {
        command.pumpOn = true;
      } else if (strcmp(value, "off") == 0) {
        command.pumpOn = false;
      } else if (strcmp(value, "auto") == 0) {
        command.pumpAuto = true;
      } else {
        return command;
      }
    } else if (strcmp(key, "light") == 0) {
      command.lightSet = true;
      if (strcmp(value, "on") == 0) {
        command.lightOn = true;
      } else if (strcmp(value, "off") == 0) {
        command.lightOn = false;
      } else if (strcmp(value, "auto") == 0) {
        command.lightAuto = true;
      } else {
        return command;
      }
    } else if (strcmp(key, "dur") == 0) {
      char* end = nullptr;
      const unsigned long seconds = strtoul(value, &end, 10);
      if (end == value || *end != '\0' || seconds < 1 || seconds > 30) {
        return command;
      }
      command.durationSeconds = static_cast<uint32_t>(seconds);
    } else if (strcmp(key, "id") == 0) {
      char* end = nullptr;
      const unsigned long id = strtoul(value, &end, 10);
      if (end == value || *end != '\0') return command;
      command.id = id;
      command.hasId = true;
    } else {
      return command;
    }
  }
  command.valid = command.pumpSet || command.lightSet;
  return command;
}

class ControlLineReader {
 public:
  enum class Result { pending, ready, rejected };

  Result push(char value) {
    if (value == '\n' || value == '\r') {
      if (length_ == 0) return Result::pending;
      line_[length_] = '\0';
      length_ = 0;
      return Result::ready;
    }
    if (length_ + 1 >= sizeof(line_)) {
      length_ = 0;
      return Result::rejected;
    }
    line_[length_++] = value;
    return Result::pending;
  }

  const char* line() const { return line_; }

 private:
  char line_[kControlLineCapacity] = {};
  size_t length_ = 0;
};

}  // namespace planter
