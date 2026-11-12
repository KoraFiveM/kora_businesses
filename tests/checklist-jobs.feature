# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_businesses — Jobs

  @kora_businesses @checklist @checklist:kora_businesses:mechanic-full-repair @cat:jobs
  Scenario: Mechanic: full garage repair
    """
    Checklist test: On-duty mechanic near an LS Customs bay (Burton/La Mesa/Route 68): ALT vehicle > Full garage repair, 18s.
    """
    Given my job is "mechanic"
    And I am on duty
    And a "test_car" is spawned in front of me
    When I manually: go to an LS Customs bay (Burton, La Mesa or Route 68)
    And I manually: hold ALT, target the vehicle and choose Full garage repair
    Then a progress bar should run
    When I wait 18 seconds
    Then I should see a notification containing "Full repair completed."
    And I confirm: the vehicle is fully repaired

  @kora_businesses @checklist @checklist:kora_businesses:mechanic-roadside @cat:jobs
  Scenario: Mechanic: roadside stabilisation
    """
    Checklist test: Target a vehicle > Roadside stabilisation (9s): engine/body raised to a floor and one tyre fixed.
    """
    Given my job is "mechanic"
    And I am on duty
    And a "test_car" is spawned in front of me
    When I manually: target the vehicle and choose Roadside stabilisation
    Then a progress bar should run
    When I wait 9 seconds
    Then I should see a notification containing "Vehicle stabilised."
    And I confirm: the vehicle engine and body health are raised to a floor value
    And I confirm: one tyre is fixed

  @kora_businesses @checklist @checklist:kora_businesses:mechanic-respray @cat:jobs
  Scenario: Mechanic: respray vehicle
    """
    Checklist test: In a shop bay target > Respray vehicle, enter primary/secondary paint indices (0-160); colours apply.
    """
    Given my job is "mechanic"
    And I am on duty
    And a "test_car" is spawned in front of me
    When I manually: go to a shop bay, target the vehicle and choose Respray vehicle
    Then a menu titled "Respray vehicle" opens
    When I manually: enter primary and secondary paint indices between 0 and 160
    Then I should see a notification containing "Respray completed."
    And I confirm: the chosen primary and secondary colours are applied to the vehicle

  @kora_businesses @checklist @checklist:kora_businesses:mechanic-bumpers @cat:jobs
  Scenario: Mechanic: customise bumpers
    """
    Checklist test: In a shop bay target > Customise bumpers with front/rear variation (-1 stock).
    """
    Given my job is "mechanic"
    And I am on duty
    And a "test_car" is spawned in front of me
    When I manually: go to a shop bay, target the vehicle and choose Customise bumpers
    Then a menu titled "Customise bumpers" opens
    When I manually: enter front and rear bumper variations (-1 is stock)
    Then I should see a notification containing "Bumper customisation completed."
    And I confirm: the front and rear bumpers show the chosen variations

  @kora_businesses @checklist @checklist:kora_businesses:mechanic-wear @cat:jobs
  Scenario: Passive vehicle wear
    """
    Checklist test: Drive a car (not bike/boat/air): extra wear lowers vehicle health with distance driven.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: drive the car for a longer distance
    Then I confirm: the vehicle health decreases with the distance driven due to extra wear
    When I manually: repeat with a bike, a boat and an aircraft
    Then I confirm: bikes, boats and aircraft do not get this wear

  @kora_businesses @checklist @checklist:kora_businesses:taxi-spawn-return @cat:jobs
  Scenario: Taxi: spawn and return taxi
    """
    Checklist test: Taxi job at the depot (909,-177): Spawn Taxi / Return Taxi target; plate TAXI.
    """
    Given my job is "unemployed"
    When I manually: ask a Mod to set my job to taxi, then go to the taxi depot at 909,-177
    And I manually: use the Spawn Taxi target
    Then I confirm: a taxi spawns with plate TAXI
    When I manually: use the Return Taxi target
    Then I confirm: the taxi is returned and removed

  @kora_businesses @checklist @checklist:kora_businesses:taxi-fare @cat:jobs
  Scenario: Taxi: pickup, dropoff and pay
    """
    Checklist test: Drive to the pickup blip, passenger enters, drive to destination; cash fare by distance.
    """
    Given my cash balance is 0
    When I manually: spawn a taxi at the depot and drive to the pickup blip
    And I manually: wait for the passenger to enter and drive to the destination
    Then I confirm: I am paid a cash fare based on distance
    And I confirm: if I am not on duty as a taxi driver I see "You must be on duty as a taxi driver." (otherwise mark Pass if nothing happens)

  @kora_businesses @checklist @checklist:kora_businesses:garbage-route @cat:jobs
  Scenario: Garbage: depot, route and payment
    """
    Checklist test: Depot (-313,-1522): Start Garbage Route; collect bins, throw bags, Return Garbage Truck; $50 per stop to bank.
    """
    Given my bank balance is at least 0
    When I manually: go to the garbage depot at -313,-1522
    And I manually: use the Start Garbage Route target
    Then I should see a notification containing "Your truck is ready. Follow the route to the first stop."
    When I manually: collect bins, throw the bags into the truck, completing every stop
    Then I should see a notification containing "Stop completed."
    When I manually: return the truck using Return Garbage Truck
    Then I confirm: my bank balance rose by $50 per stop

  @kora_businesses @checklist @checklist:kora_businesses:recycle-clock @cat:jobs @manual
  Scenario: Recycling: clock in/out and warehouse
    """
    Checklist test: Recycle Center: enter warehouse target, toggle duty; exit warehouse.
    """
    When I manually: go to the Recycle Center and use the enter warehouse target
    Then I confirm: I am inside the warehouse
    When I manually: toggle duty using the target
    Then I confirm: my duty status toggles
    When I manually: exit the warehouse
    Then I confirm: I am back outside the warehouse

  @kora_businesses @checklist @checklist:kora_businesses:recycle-packages @cat:jobs @manual
  Scenario: Recycling: pick up and hand in packages
    """
    Checklist test: Take a package from shelf, carry, hand in; receive random scrap materials (metalscrap, plastic, copper...).
    """
    When I manually: take a package from a shelf in the recycling warehouse
    And I manually: carry the package and hand it in
    Then I confirm: I receive random scrap materials such as metalscrap, plastic or copper

  @kora_businesses @checklist @checklist:kora_businesses:recycle-sell @cat:jobs
  Scenario: Recycling: sell materials
    """
    Checklist test: Use the sell target to sell recycled materials; too far shows an error.
    """
    Given I have 5 "metalscrap"
    And I have 5 "plastic"
    When I manually: use the recycling sell target while standing close
    Then I confirm: the materials are sold and I receive payment
    When I manually: try the sell target from too far away
    Then I confirm: an error is shown

  @kora_businesses @checklist @checklist:kora_businesses:tow-job @cat:jobs
  Scenario: Tow: pick up and drop vehicles
    """
    Checklist test: Take a flatbed (489,-1331); at tow spot use Tow Vehicle, then Place Vehicle at drop; $100 each to bank.
    """
    Given my job is "tow"
    And I am on duty
    When I manually: go to 489,-1331 and take a flatbed
    And I manually: at a tow spot, use Tow Vehicle
    Then I should see a notification containing "New tow vehicle marked on your map"
    When I manually: drive to the drop and use Place Vehicle
    Then I should see a notification containing "You received $"
    And I confirm: I received $100 per vehicle to my bank

  @kora_businesses @checklist @checklist:kora_businesses:tow-vehicle-ops @cat:jobs
  Scenario: Tow: pull out, detach and store
    """
    Checklist test: Targets Pull Out Vehicle, Detach Vehicle and Store Vehicle at the tow yard.
    """
    Given my job is "tow"
    And I am on duty
    When I manually: go to the tow yard and use the Pull Out Vehicle target
    Then I confirm: a tow vehicle is pulled out
    When I manually: use the Detach Vehicle target
    Then I confirm: the vehicle is detached
    When I manually: use the Store Vehicle target
    Then I confirm: the vehicle is stored

  @kora_businesses @checklist @checklist:kora_businesses:cctv-laptop @cat:jobs
  Scenario: CCTV engineer laptop
    """
    Checklist test: On-duty cctv job uses cctv_laptop item: AppShell shows installed systems and call-outs.
    """
    When I manually: ask a Mod to set my job to cctv and put me on duty, and give me a cctv_laptop item
    And I manually: use the cctv_laptop item
    Then the "kora_businesses:cctv-laptop" app opens
    And I confirm: the app shows installed systems and call-outs

  @kora_businesses @checklist @checklist:kora_businesses:cctv-callouts @cat:jobs @manual
  Scenario: CCTV call-outs
    """
    Checklist test: Business member requests camera/NVR callout; engineer lists, accepts, completes; charge $250/$750 goes to CCTV society.
    """
    When I manually: as a business member, request a camera or NVR callout
    And I manually: as the on-duty CCTV engineer, list the call-outs, accept one and complete it
    Then I confirm: the charge of $250 (camera) or $750 (NVR) goes to the CCTV society account

  @kora_businesses @checklist @checklist:kora_businesses:cctv-hack-repair @cat:jobs
  Scenario: CCTV hack and repair (/cctvhack, /cctvrepair)
    """
    Checklist test: Run /cctvhack <id> and /cctvrepair <id>: minigame in private bucket, result notify.
    """
    When I manually: get a valid id (ask a second player) and run /cctvhack with that id
    Then I confirm: a minigame starts in a private bucket
    And I should see a notification containing "Access granted:"
    When I manually: run /cctvrepair with the same id
    Then I confirm: a minigame starts in a private bucket
    And I should see a notification containing "Repair check passed:"

  @kora_businesses @checklist @checklist:kora_businesses:hotdog-stand @cat:jobs
  Scenario: Hotdog stand job
    """
    Checklist test: If enabled: Start Working at stand point, pay $250 deposit, prepare dogs (minigame), sell to peds, G drops stand. Verify it is loaded.
    """
    Given my cash balance is 500
    When I manually: go to the hotdog stand point
    And I manually: use Start Working and pay the $250 deposit (only applies if the hotdog job is enabled; otherwise mark Pass if nothing happens)
    Then my cash balance should have changed by -250
    When I manually: prepare hotdogs through the minigame
    And I manually: sell hotdogs to peds
    And I manually: press G to drop the stand
    Then I confirm: the stand is dropped

  @kora_businesses @checklist @checklist:kora_businesses:hotdog-removestand @cat:jobs @manual
  Scenario: Admin /removestand
    """
    Checklist test: Admin runs /removestand near a hotdog stand to delete it.
    """
    When I manually: ask a Mod to run /removestand near a hotdog stand
    Then I confirm: the hotdog stand is deleted
