-- Shop item lists. A POS module references a list by name; every item in that
-- list may be stocked at that till, and any item carrying a `price` is FIXED at
-- that price -- an employee restocking it is never asked to set one and a boss
-- cannot reprice it in-game.
--
-- An item with no `price` is allowed but priced by whoever first stocks it, and
-- that price is then remembered for the till.
--
-- A POS module with no list at all accepts any item, always employee-priced.

Config.shopItems['burgershot'] = {
    { item = 'burger', price = 12 },
    { item = 'fries', price = 8 },
    { item = 'water_bottle', price = 5 },
    { item = 'sprunk' },
}
