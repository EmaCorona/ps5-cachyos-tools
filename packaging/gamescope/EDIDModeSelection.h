#pragma once

#include <vector>

namespace gamescope
{
	template <typename Mode, typename TryMode>
	const Mode *FindFirstUsableEDIDMode( const std::vector<Mode> &modes, TryMode &&tryMode )
	{
		for ( const Mode &mode : modes )
		{
			if ( const Mode *usableMode = tryMode( mode ) )
				return usableMode;
		}
		return nullptr;
	}
}
