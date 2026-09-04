// 140K Apple II/III sector-image to 6-and-2 NIB conversion for simulation.
//
// The layout follows the Disk II field format and sector ordering used by
// MiSTer's live dsk2nib path.  Keeping this conversion in the test harness lets
// an unmodified Apple III system disk exercise the RTL floppy controller.
#pragma once

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <fstream>
#include <string>
#include <vector>

namespace apple3_disk_image {

constexpr std::size_t kTracks = 35;
constexpr std::size_t kSectors = 16;
constexpr std::size_t kSectorBytes = 256;
constexpr std::size_t kTrackBytes = 0x1a00;
constexpr std::size_t kDskBytes = kTracks * kSectors * kSectorBytes;
constexpr std::size_t kNibBytes = kTracks * kTrackBytes;

static const std::array<uint8_t, 64> kGcr = {
	0x96, 0x97, 0x9a, 0x9b, 0x9d, 0x9e, 0x9f, 0xa6,
	0xa7, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb2, 0xb3,
	0xb4, 0xb5, 0xb6, 0xb7, 0xb9, 0xba, 0xbb, 0xbc,
	0xbd, 0xbe, 0xbf, 0xcb, 0xcd, 0xce, 0xcf, 0xd3,
	0xd6, 0xd7, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde,
	0xdf, 0xe5, 0xe6, 0xe7, 0xe9, 0xea, 0xeb, 0xec,
	0xed, 0xee, 0xef, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6,
	0xf7, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
};

inline void encode44(std::vector<uint8_t>& out, uint8_t value) {
	out.push_back((value >> 1) | 0xaa);
	out.push_back(value | 0xaa);
}

// A sector image cannot represent the address-field volume bytes used by the
// Apple III's synchronized-track protection check.  Apple's BFM.INIT2 reads
// this eight-byte key from tracks 9 through 16 before decoding the kernel.
// This is the standard key emitted by a3dsk2woz for Apple III DSK images.
inline uint8_t apple3_volume(std::size_t track, std::size_t sector) {
	static constexpr std::array<uint8_t, 8> key = {
		0xb4, 0xc1, 0xe4, 0xf3, 0x9b, 0xbd, 0xbd, 0x7c
	};
	static constexpr std::array<uint8_t, 8> key_sector = {
		2, 14, 10, 6, 2, 14, 10, 6
	};
	if (track >= 9 && track <= 16 && sector == key_sector[track - 9])
		return key[track - 9];
	return 0xfe;
}

inline void encode62(std::vector<uint8_t>& out, const uint8_t* sector) {
	static constexpr std::array<uint8_t, 4> swap_low_bits = {0, 2, 1, 3};
	std::array<uint8_t, 256> primary{};
	std::array<uint8_t, 86> secondary{};

	secondary[0] = swap_low_bits[sector[1] & 3];
	secondary[1] = swap_low_bits[sector[0] & 3];
	for (int source = 255, target = 2; source >= 0;
	     --source, target = (target == 85) ? 0 : target + 1) {
		secondary[target] = (secondary[target] << 2) |
		                    swap_low_bits[sector[source] & 3];
		primary[source] = sector[source] >> 2;
	}
	for (auto& value : secondary) value &= 0x3f;

	uint8_t previous = 0;
	for (int index = 85; index >= 0; --index) {
		out.push_back(kGcr[previous ^ secondary[index]]);
		previous = secondary[index];
	}
	for (const uint8_t value : primary) {
		out.push_back(kGcr[previous ^ value]);
		previous = value;
	}
	out.push_back(kGcr[previous]);
}

inline std::string lowercase_extension(const std::string& path) {
	const auto dot = path.find_last_of('.');
	if (dot == std::string::npos) return {};
	std::string extension = path.substr(dot);
	std::transform(extension.begin(), extension.end(), extension.begin(),
	               [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return extension;
}

inline bool load(const std::string& path, std::vector<uint8_t>& nib,
	             std::string& error) {
	std::ifstream input(path, std::ios::binary);
	if (!input) {
		error = "cannot open " + path;
		return false;
	}
	std::vector<uint8_t> source((std::istreambuf_iterator<char>(input)), {});
	const std::string extension = lowercase_extension(path);
	if (extension == ".nib") {
		if (source.size() != kNibBytes) {
			error = "NIB image must be 232960 bytes";
			return false;
		}
		nib = std::move(source);
		return true;
	}
	if ((extension != ".dsk" && extension != ".do" && extension != ".po") ||
	    source.size() != kDskBytes) {
		error = "disk image must be a 143360-byte DSK/DO/PO or 232960-byte NIB";
		return false;
	}

	static constexpr std::array<int, 16> dos_order = {
		0x0, 0x7, 0xe, 0x6, 0xd, 0x5, 0xc, 0x4,
		0xb, 0x3, 0xa, 0x2, 0x9, 0x1, 0x8, 0xf
	};
	static constexpr std::array<int, 16> prodos_order = {
		0x0, 0xe, 0xd, 0xc, 0xb, 0xa, 0x9, 0x8,
		0x7, 0x6, 0x5, 0x4, 0x3, 0x2, 0x1, 0xf
	};
	const bool prodos = extension == ".po";
	nib.assign(kNibBytes, 0xff);

	for (std::size_t track = 0; track < kTracks; ++track) {
		std::vector<uint8_t> encoded;
		encoded.reserve(kTrackBytes);
		for (std::size_t physical = 0; physical < kSectors; ++physical) {
			encoded.insert(encoded.end(), 38, 0xff);
			encoded.insert(encoded.end(), {0xd5, 0xaa, 0x96});
			const uint8_t volume = apple3_volume(track, physical);
			encode44(encoded, volume);
			encode44(encoded, static_cast<uint8_t>(track));
			encode44(encoded, static_cast<uint8_t>(physical));
			encode44(encoded, static_cast<uint8_t>(volume ^ track ^ physical));
			encoded.insert(encoded.end(), {0xde, 0xaa, 0xeb});
			encoded.insert(encoded.end(), 8, 0xff);
			encoded.insert(encoded.end(), {0xd5, 0xaa, 0xad});

			const int ordered = prodos ? prodos_order[physical]
			                           : static_cast<int>(physical);
			const std::size_t source_sector = track * kSectors + dos_order[ordered];
			encode62(encoded, source.data() + source_sector * kSectorBytes);
			encoded.insert(encoded.end(), {0xde, 0xaa, 0xeb});
		}
		if (encoded.size() > kTrackBytes) {
			error = "internal NIB track overflow";
			return false;
		}
		std::copy(encoded.begin(), encoded.end(), nib.begin() + track * kTrackBytes);
	}
	return true;
}

} // namespace apple3_disk_image
