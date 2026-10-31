Recycle = {
	OutsideLocation         = vector4(55.55, 6472.18, 31.43, 44.0),
	InsideLocation          = vector4(1073.0, -3102.49, -39.0, 266.61),
	DutyLocation            = vector4(1048.7, -3100.62, -38.2, 88.02),
	DropLocation            = vector4(1048.224, -3097.071, -38.999, 274.810),
	SellMaterials           = true, --  allow players to sell materials to a ped
	LimitedMaterials        = true, -- limit the amount of materials that can be sold
	SellPed                 = vector4(1049.84, -3094.08, -40.0, 178.84),
	DrawPackageLocationBlip = true,
	PickupActionDuration    = math.random(4000, 6000),
	DeliveryActionDuration  = 5000,
	-- Carry prop shown in the player's hands between "Get Package" and "Hand In Package".
	PickupBoxModel          = 'prop_cs_cardbox_01', -- any valid base-game (or streamed) prop model
	CarryPropNetworked      = true,                 -- true: other players see the box; false: local-only prop
	CarryBone               = 57005,                -- ped bone id: 57005 = right hand (28422 = right hand IK, 60309 = left hand)
	CarryOffset             = vector3(0.05, 0.1, -0.3),        -- attach offset relative to the bone
	CarryRotation           = vector3(300.0, 250.0, 20.0),     -- attach rotation relative to the bone
	CarryAnim               = {                                -- carry pose; flag 49 = loop + upper body only, so the player can walk
		dict = 'anim@heists@box_carry@',
		clip = 'idle',
		flag = 49,
	},
	PickupLocations         = {
		{ model = math.random(1, 7), loc = vector4(1067.68, -3095.57, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1065.20, -3095.57, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1062.73, -3095.57, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1060.37, -3095.57, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1057.95, -3095.57, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1055.58, -3095.57, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1053.09, -3095.57, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1053.07, -3102.62, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1055.49, -3102.62, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1057.93, -3102.62, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1060.19, -3102.62, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1062.71, -3102.62, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1065.19, -3102.62, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1067.46, -3102.62, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1067.69, -3109.71, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1065.13, -3109.71, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1062.70, -3109.71, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1060.24, -3109.71, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1057.76, -3109.71, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1055.52, -3109.71, -39.9, 342.39), },
		{ model = math.random(1, 7), loc = vector4(1053.16, -3109.71, -39.9, 342.39), },
	},

	WarehouseObjects        = {
		'prop_boxpile_05a',
		'prop_boxpile_04a',
		'prop_boxpile_06b',
		'prop_boxpile_02c',
		'prop_boxpile_02b',
		'prop_boxpile_01a',
		'prop_boxpile_08a',
	},
}

Globals.Recycle = Recycle