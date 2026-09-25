Cctv = {
    job = 'cctv',
    laptopItem = 'cctv_laptop',
    requireOnDuty = true,
    minimumEngineerGrade = 0,
    hacking = {
        enabled = true,
        skill = 'crafting',
        game = 'hacking',
        options = { solutionsize = 4, timeLimit = 30000 },
        privateBucketBase = 7000,
        duration = 120000,
    },
    repairChecks = {
        enabled = true,
        skill = 'computing',
        game = 'circuit',
        baseNodes = 4,
        nodesPerSecurityLevel = 1,
        duration = 120000,
    },
    callouts = {
        enabled = true,
        charge = 500,
        requireEngineerOnline = true,
        allowWhenSubscriptionSuspended = true,
    },
    repair = {
        cameraPrice = 250,
        nvrPrice = 750,
    },
}

Globals.Cctv = Cctv
