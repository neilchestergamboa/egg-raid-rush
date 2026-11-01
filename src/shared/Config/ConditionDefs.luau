--!strict

export type ConditionDefinition = {
    Name: string,
    PowerMultiplier: number,
    RollWeight: number,
}

return {
    Cracked = {
        Name = "Cracked",
        PowerMultiplier = 0.70,
        RollWeight = 35,
    },
    Scuffed = {
        Name = "Scuffed",
        PowerMultiplier = 0.85,
        RollWeight = 30,
    },
    Sturdy = {
        Name = "Sturdy",
        PowerMultiplier = 1.00,
        RollWeight = 22,
    },
    Polished = {
        Name = "Polished",
        PowerMultiplier = 1.20,
        RollWeight = 10,
    },
    Flawless = {
        Name = "Flawless",
        PowerMultiplier = 1.50,
        RollWeight = 3,
    },
}
