--!strict

local function publish(target: Instance, record: any)
    target:SetAttribute("Uid", record.Uid)
    target:SetAttribute("DefId", record.DefId)
    target:SetAttribute("ZoneId", record.ZoneId)
    target:SetAttribute("Slot", record.Slot)
    target:SetAttribute("RarityId", record.RarityId)
    target:SetAttribute("IsTutorial", record.IsTutorial)
    target:SetAttribute("RespawnSeconds", record.RespawnSeconds)
    target:SetAttribute("State", record.State)
    target:SetAttribute("ClaimantUserId", record.ClaimantUserId)
    target:SetAttribute("ExpiresAt", record.ExpiresAt)
    target:SetAttribute("CreatureUid", record.CreatureUid)
    target:SetAttribute("CarrierUserId", record.CarrierUserId)
    target:SetAttribute("PreviousCarrierUserId", record.PreviousCarrierUserId)
    target:SetAttribute("PickupLockoutUntil", record.PickupLockoutUntil)
    target:SetAttribute("DropExpiresAt", record.DropExpiresAt)
    target:SetAttribute("DropPosition", record.DropPosition)
    if
        record.State == "Fighting"
        or record.State == "Won"
        or record.State == "Carried"
        or record.State == "Dropped"
        or record.State == "Banked"
    then
        target:SetAttribute("ConditionRoll", record.ConditionRoll)
    else
        target:SetAttribute("ConditionRoll", nil)
    end
    if
        record.State ~= "Fighting"
        and record.State ~= "Won"
        and record.State ~= "Carried"
        and record.State ~= "Dropped"
        and record.State ~= "Banked"
    then
        for _, attributeName in
            {
                "FightElapsedSeconds",
                "FightDurationSeconds",
                "PetHp",
                "PetMaxHp",
                "HatchlingHp",
                "HatchlingMaxHp",
                "FightSeed",
                "FightStatus",
                "FightResult",
            }
        do
            target:SetAttribute(attributeName, nil)
        end
    end

    if record.State ~= "Breaking" then
        target:SetAttribute("Health", nil)
        target:SetAttribute("MaxHealth", nil)
        target:SetAttribute("CrackStage", nil)
    end
end

return { Publish = publish }
