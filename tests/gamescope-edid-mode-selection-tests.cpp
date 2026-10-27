#include "../packaging/gamescope/EDIDModeSelection.h"

#include <cassert>
#include <vector>

struct TestMode
{
	int width;
	int height;
	int refresh;
};

int main()
{
	const std::vector<TestMode> modes = {
		{ 3440, 1440, 100 },
		{ 3440, 1440, 60 },
		{ 1920, 1080, 60 },
	};
	std::vector<int> triedRefreshRates;
	const TestMode *selected = gamescope::FindFirstUsableEDIDMode( modes, [&]( const TestMode &mode ) -> const TestMode *
	{
		triedRefreshRates.push_back( mode.refresh );
		return mode.refresh == 60 && mode.width == 3440 ? &mode : nullptr;
	} );
	assert( selected == &modes[1] );
	assert( ( triedRefreshRates == std::vector<int>{ 100, 60 } ) );

	triedRefreshRates.clear();
	const TestMode *standardAspect = gamescope::FindFirstUsableEDIDMode( modes, [&]( const TestMode &mode ) -> const TestMode *
	{
		triedRefreshRates.push_back( mode.refresh );
		return mode.width == 1920 ? &mode : nullptr;
	} );
	assert( standardAspect == &modes[2] );
	assert( triedRefreshRates.size() == modes.size() );

	triedRefreshRates.clear();
	const TestMode *none = gamescope::FindFirstUsableEDIDMode( modes, [&]( const TestMode &mode ) -> const TestMode *
	{
		triedRefreshRates.push_back( mode.refresh );
		return nullptr;
	} );
	assert( none == nullptr );
	assert( triedRefreshRates.size() == modes.size() );

	const std::vector<TestMode> noModes;
	assert( gamescope::FindFirstUsableEDIDMode( noModes, []( const TestMode &mode ) -> const TestMode *
	{
		return &mode;
	} ) == nullptr );
}
