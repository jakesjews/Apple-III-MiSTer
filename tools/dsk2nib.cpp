#include "../sim/coretest/dsk2nib.h"

#include <fstream>
#include <iostream>
#include <string>
#include <vector>

int main(int argc, char** argv) {
	if (argc != 3) {
		std::cerr << "usage: dsk2nib INPUT.{dsk,do,po} OUTPUT.nib\n";
		return 2;
	}

	std::vector<uint8_t> image;
	std::string error;
	if (!apple3_disk_image::load(argv[1], image, error)) {
		std::cerr << "dsk2nib: " << error << '\n';
		return 1;
	}

	std::ofstream output(argv[2], std::ios::binary | std::ios::trunc);
	if (!output) {
		std::cerr << "dsk2nib: cannot create " << argv[2] << '\n';
		return 1;
	}
	output.write(reinterpret_cast<const char*>(image.data()),
	             static_cast<std::streamsize>(image.size()));
	if (!output) {
		std::cerr << "dsk2nib: failed writing " << argv[2] << '\n';
		return 1;
	}

	std::cout << "wrote " << image.size() << " bytes to " << argv[2] << '\n';
	return 0;
}
