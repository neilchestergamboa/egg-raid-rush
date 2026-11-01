--!strict

export type GuardDefinition = {
    Name: string,
    ZoneId: number,
    Speed: number,
    IsTutorial: boolean,
    ForgiveFirstDrop: boolean,
}

return {
    guard_pride_king = {
        Name = "Pride King",
        ZoneId = 1,
        Speed = 12,
        IsTutorial = false,
        ForgiveFirstDrop = false,
    },
    guard_pride_king_tutorial = {
        Name = "Pride King",
        ZoneId = 1,
        Speed = 8,
        IsTutorial = true,
        ForgiveFirstDrop = true,
    },
}
