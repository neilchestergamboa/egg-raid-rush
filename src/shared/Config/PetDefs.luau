--!strict

export type PetDefinition = {
    Name: string,
    Description: string,
    ZoneId: number,
    RarityId: string,
    BasePower: number,
    Gps: number,
    BodySize: "Small" | "Medium" | "Large",
}

return {
    pet_jackal_pup = {
        Name = "Jackal Pup",
        Description = "Quick scrappy pup with oversized ears.",
        ZoneId = 1,
        RarityId = "Common",
        BasePower = 120,
        Gps = 1,
        BodySize = "Small",
    },
    pet_hyena_pup = {
        Name = "Hyena Pup",
        Description = "Spotted pup with a cheeky grin.",
        ZoneId = 1,
        RarityId = "Common",
        BasePower = 120,
        Gps = 1,
        BodySize = "Medium",
    },
    pet_wild_dog_pup = {
        Name = "Wild Dog Pup",
        Description = "Painted-coat pack hunter.",
        ZoneId = 1,
        RarityId = "Uncommon",
        BasePower = 150,
        Gps = 6,
        BodySize = "Medium",
    },
    pet_cheetah_cub = {
        Name = "Cheetah Cub",
        Description = "Fastest cub on the savanna.",
        ZoneId = 1,
        RarityId = "Rare",
        BasePower = 180,
        Gps = 40,
        BodySize = "Medium",
    },
    pet_leopard_cub = {
        Name = "Leopard Cub",
        Description = "Spotted climber that naps in trees.",
        ZoneId = 1,
        RarityId = "Epic",
        BasePower = 225,
        Gps = 250,
        BodySize = "Large",
    },
    pet_lion_cub = {
        Name = "Lion Cub",
        Description = "Golden cub with a tiny mane.",
        ZoneId = 1,
        RarityId = "Legendary",
        BasePower = 270,
        Gps = 1800,
        BodySize = "Large",
    },
}
