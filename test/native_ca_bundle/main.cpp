#include "ca_bundle.h"
#include <fstream>
#include <iostream>
#include <iterator>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  std::ifstream file(argv[1], std::ios::binary);
  if (!file) return 3;
  const std::string expected((std::istreambuf_iterator<char>(file)), {});
  const auto &actual = eh_ca_bundle();
  if (expected.empty() || actual != expected) {
    std::cerr << "CA bundle differs from the original PEM\n";
    return 1;
  }
  std::cout << "Complete CA bundle preserved: " << actual.size() << " bytes\n";
  return 0;
}
