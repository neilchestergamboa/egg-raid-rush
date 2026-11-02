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

    if record.State ~= "Breaking" then
        target:SetAttribute("Health", nil)
        target:SetAttribute("MaxHealth", nil)
        target:SetAttribute("CrackStage", nil)
    end
end

return { Publish = publish }
