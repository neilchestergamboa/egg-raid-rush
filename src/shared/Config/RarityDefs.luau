--!strict

export type RarityDefinition = {
    Name: string,
    PowerMultiplier: number,
    BreakSeconds: number,
    RespawnSeconds: number,
    BaseGps: number,
}

return {
    Common = {
        Name = "Common",
        PowerMultiplier = 0.40,
        BreakSeconds = 8,
        RespawnSeconds = 25,
        BaseGps = 1,
    },
    Uncommon = {
        Name = "Uncommon",
        PowerMultiplier = 0.50,
        BreakSeconds = 9,
        RespawnSeconds = 40,
        BaseGps = 6,
    },
    Rare = {
        Name = "Rare",
        PowerMultiplier = 0.60,
        BreakSeconds = 10,
        RespawnSeconds = 60,
        BaseGps = 40,
    },
    Epic = {
        Name = "Epic",
        PowerMultiplier = 0.75,
        BreakSeconds = 12,
        RespawnSeconds = 90,
        BaseGps = 250,
    },
    Legendary = {
        Name = "Legendary",
        PowerMultiplier = 0.90,
        BreakSeconds = 14,
        RespawnSeconds = 150,
        BaseGps = 1800,
    },
}
