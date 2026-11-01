--!strict

export type ZoneDefinition = {
    Id: number,
    Name: string,
    Theme: string,
    RecommendedPetPower: number,
    GuardDefId: string,
    EggDefIds: { string },
    TutorialEggDefId: string,
}

return {
    Zone1 = {
        Id = 1,
        Name = "Savanna Pride Lands",
        Theme = "Golden grassland with acacia trees, watering holes, and rocky outcrops.",
        RecommendedPetPower = 300,
        GuardDefId = "guard_pride_king",
        EggDefIds = {
            "egg_z1_slot_1",
            "egg_z1_slot_2",
            "egg_z1_slot_3",
            "egg_z1_slot_4",
            "egg_z1_slot_5",
            "egg_z1_slot_6",
        },
        TutorialEggDefId = "egg_z1_tutorial",
    },
}
