-- UI hints and authority use the same policy. Never trust a client permission flag.
local Access = {}

function Access.allowed(player)
    if not player or player:isDead() then
        return false
    end
    if SandboxVars and SandboxVars.ProjectPeople and SandboxVars.ProjectPeople.DebugEnabled == true then
        return true
    end
    if isServer() or isClient() then
        if player.getRole and Capability and Capability.UseDebugContextMenu then
            local role = player:getRole()
            return role
                    and (role:hasCapability(Capability.UseDebugContextMenu) or Capability.GeneralCheats and role:hasCapability(
                        Capability.GeneralCheats
                    ))
                or false
        end
        return player.getAccessLevel and player:getAccessLevel() == "admin" or false
    end
    return isDebugEnabled and isDebugEnabled() or false
end

return Access
