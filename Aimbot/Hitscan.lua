---@alias Target {Player: Entity, TargetType: "CTFPlayer", vPos: Vector3, vAngleTo: EulerAngles, flFOVTo: number, Hitbox: integer, bHasMultiPointed: boolean}

--- CONSTANTS ---
local HITBOX_HEAD, HITBOX_SPINE = 1, 4
local SYDNEY_SLEEPER, AMBASSADOR, FESTIVE_AMBASSADOR = 230, 61, 1006 -- weapon ids

---@param localplayer Entity
---@param weapon Entity
---@return integer
local function GetAimPosition(localplayer, weapon)
	local position = gui.GetValue("aim position")
	if position == "head" then return HITBOX_HEAD end
	if position == "body" then return HITBOX_SPINE end

	if position == "hit scan" then
		local class = localplayer:GetPropInt("m_iClass")
		local item_def_idx = weapon:GetPropInt("m_iItemDefinitionIndex")
		
		if class == TF2_Sniper then

			if item_def_idx ~= SYDNEY_SLEEPER then
				return localplayer:InCond(E_TFCOND.TFCond_Zoomed) and HITBOX_HEAD or HITBOX_SPINE
			end

			return HITBOX_SPINE

		elseif class == TF2_Spy then
			local IsAmbassador = (item_def_idx == AMBASSADOR) or (item_def_idx == FESTIVE_AMBASSADOR)
			return IsAmbassador and HITBOX_HEAD or HITBOX_SPINE

		else
			return HITBOX_SPINE
		end
	end

	return HITBOX_SPINE
end

---@param localplayer Entity
---@param weapon Entity
local function GetShootPos(localplayer, weapon)
	return (localplayer:GetAbsOrigin() + weapon:GetPropVector("m_vecViewOffset[0]"))
end

---@param source Vector3
---@param dest Vector3
---@return EulerAngles
local function CalculateAngle(source, dest)
	local angles = EulerAngles()
	local delta = source - dest

	angles.pitch = math.atan(delta.z/ delta:Length2D()) * (180 / math.pi )
	angles.yaw = math.atan(delta.y, delta.x) * (180 / math.pi)

	if delta.x > 0 then
		angles.yaw = angles.yaw + 180

	elseif delta.x < 0 then
		angles.yaw = angles.yaw - 180
	end

	return angles
end

---@param source EulerAngles
---@param dest EulerAngles
local function CalculateFOV(source, dest)
	local v_source = source:Forward()
	local v_dest = dest:Forward()
	local result = math.deg ( math.acos(v_dest:Dot(v_source) / v_dest:LengthSqr()) )
	if result == "inf" or result ~= result then
		result = 0
	end
	return result
end

---@param player Entity
local function GetHitboxPos(player, hitbox)
	local model = player:GetModel()
	local studioHdr = models.GetStudioModel(model)

	local pHitBoxSet = player:GetPropInt("m_nHitboxSet")
	local hitboxSet = studioHdr:GetHitboxSet(pHitBoxSet)
	local hitboxes = hitboxSet:GetHitboxes()

	local hitbox = hitboxes[hitbox]
	local bone = hitbox:GetBone()

	local boneMatrices = player:SetupBones()
	local boneMatrix = boneMatrices[bone]
	if boneMatrix then
		local bonePos = Vector3( boneMatrix[1][4], boneMatrix[2][4], boneMatrix[3][4] )
		return bonePos
	end
	return nil
end

---@param localplayer Entity
---@param weapon Entity
local function GetTargets(localplayer, weapon)
	local targets = {}
	local vLocalPos = GetShootPos(localplayer, weapon)
	local vLocalAngles = engine:GetViewAngles()
	local players = entities.FindByClass("CTFPlayer")

	local aimPos = GetAimPosition(localplayer, weapon)

	for _, player in pairs (players) do
		if player:GetTeamNumber() == localplayer:GetTeamNumber() then goto continue end

		if player:IsDormant() then goto continue end
		
		if not player:IsAlive() then goto continue end
		
		if gui.GetValue("ignore cloaked") == 1 and player:InCond(E_TFCOND.TFCond_Cloaked) then goto continue end
	
		if gui.GetValue("ignore disguised") == 1 and player:InCond(E_TFCOND.TFCond_Disguised) then goto continue end
	
		if gui.GetValue("ignore taunting") == 1 and player:InCond(E_TFCOND.TFCond_Taunting) then goto continue end
	
		if gui.GetValue("ignore bonked") == 1 and player:InCond(E_TFCOND.TFCond_Bonked) then goto continue end
	
		if gui.GetValue("ignore deadringer") == 1 and player:InCond(E_TFCOND.TFCond_DeadRingered) then goto continue end

		if player:InCond(E_TFCOND.TFCond_Ubercharged) then goto continue end

		local vPos = GetHitboxPos(player, aimPos)
		if not vPos then goto continue end

		local vAngleTo = CalculateAngle(vLocalPos, vPos)
		local flFOVTo = CalculateFOV(vLocalAngles, vAngleTo)
		if flFOVTo > gui.GetValue("aim fov") then goto continue end

		targets[#targets+1] = {Player = player, TargetType = "CTFPlayer", vPos = vPos, vAngleTo = vAngleTo, flFOVTo = flFOVTo, Hitbox = aimPos}
		::continue::
	end

	return targets
end

local function VisPos(entity, source, dest)
	local trace = engine.TraceLine(source, dest, (MASK_SHOT | CONTENTS_GRATE))
	if trace.entity then
		return (trace.entity == entity) or (trace.fraction > 0.99)
	else
		return false
	end
end

---@param entity Entity
---@param source Vector3
---@param dst Vector3
---@param hitbox integer
local function VisPosHitboxId(entity, source, dst, hitbox)
	local trace = engine.TraceLine(source, dst, (MASK_SHOT | CONTENTS_GRATE))
	return (trace.entity and trace.entity == entity and trace.hitbox == hitbox)
end

---@param entity Entity
---@param src Vector3
---@param dst Vector3
local function VisPosHitboxIdOut(entity, src, dst)
	local trace = engine.TraceLine(src, dst, (MASK_SHOT | CONTENTS_GRATE))
	if trace.entity and trace.entity == entity then
		return true
	end
	return false
end

---@param input Vector3
---@param matrix Matrix3x4
---@param output Vector3
local function VectorTransform(input, matrix)
	local output = Vector3()
	for i = 1, 3 do
		output[i] = input:Dot(matrix[i] + matrix[i][3])
	end
	return output
end

---@param localplayer Entity
---@param target Target
local function ScanHitboxes(localplayer, target)
	local vLocalPos = GetShootPos(localplayer, localplayer:GetPropEntity("m_hActiveWeapon"))
	if target.Hitbox == HITBOX_SPINE then return target end

	local vHitbox = GetHitboxPos(target.Player, target.Hitbox)

	if VisPos(target.Player, vLocalPos, vHitbox) then
		target.vPos = vHitbox
		target.vAngleTo = CalculateAngle(vLocalPos, vHitbox)
	end

	return target
end

---@param target Target
local function ScanHead(localplayer, target)
	local player = target.Player
	local model = player:GetModel()
	local studioHdr = models.GetStudioModel(model)

	local pHitBoxSet = player:GetPropInt("m_nHitboxSet")
	local hitboxSet = studioHdr:GetHitboxSet(pHitBoxSet)
	local hitboxes = hitboxSet:GetHitboxes()

	local hitbox = hitboxes[HITBOX_HEAD]
	local bone = hitbox:GetBone()
	local boneMatrices = player:SetupBones()
	local boneMatrix = boneMatrices[bone]

	local vMins, vMaxs = hitbox:GetBBMin(), hitbox:GetBBmax()

	local vLocalPos = GetShootPos(localplayer, localplayer:GetPropEntity("m_hActiveWeapon"))

	local fScale = 0.8

	local vecPoints = {
		Vector3(((vMins.x + vMaxs.x) * 0.5), (vMins.y * fScale), ((vMins.z + vMaxs.z) * 0.5)),
		Vector3((vMins.x * fScale), ((vMins.y + vMaxs.y) * 0.5), ((vMins.z + vMaxs.z) * 0.5)),
		Vector3((vMaxs.x * fScale), ((vMins.y + vMaxs.y) * 0.5), ((vMins.z + vMaxs.z) * 0.5))
	}

	for _, Point in ipairs(vecPoints) do
		local vTransformed = VectorTransform(Point, boneMatrix)
		if VisPosHitboxId(target.Player, vLocalPos, vTransformed, HITBOX_HEAD) then
			target.vPos = vTransformed
			target.vAngleTo = CalculateAngle(vLocalPos, vTransformed)
		   target.bHasMultiPointed = true
		end
  end
  return target
end

---@param localplayer Entity
---@param weapon Entity
---@param target Target
local function VerifyTarget(localplayer, weapon, target)
	if target.Hitbox == HITBOX_HEAD then
		if (not VisPosHitboxIdOut(target.Player, GetShootPos(localplayer, weapon), target.vPos)) or (not ScanHead(localplayer, target)) then
			return false
		end

	elseif target.Hitbox == HITBOX_PELVIS then
		if (not VisPos(target.Player, GetShootPos(localplayer, weapon), target.vPos)) or (not ScanHitboxes(localplayer, target)) then
			return false
		end

	else
		if not VisPos(target.Player, GetShootPos(localplayer, weapon), target.vPos) then
			return false
		end
	end

	return true
end

---@return Target
local function GetTarget(localplayer, weapon)
	local targets = GetTargets(localplayer, weapon)
	if not targets or #targets == 0 then return nil end

	local out = nil

	for _, target in pairs (targets) do
		if not VerifyTarget(localplayer, weapon, target) then goto endloop1 end
		out = target
		::endloop1::
	end

	return out
end

---@param usercmd UserCmd
---@param angle Vector3
local function Aim(usercmd, angle)
	local localplayer = entities.GetLocalPlayer()
	if not localplayer then return end

	local vPunchAngles = localplayer:GetPropVector("m_vecPunchAngle")
	angle = angle - vPunchAngles

	local method = gui.GetValue("aim method")

	if method == "plain" then
		usercmd.viewangles = angle
		engine.SetViewAngles(EulerAngles(angle.x, angle.y, angle.z))

	elseif method == "smooth" then
		local engineView = engine:GetViewAngles()
		local delta = angle - Vector3(engineView.pitch, engineView.yaw, engineView.roll)
		usercmd.viewangles = usercmd.viewangles + delta / gui.GetValue("smooth value")
		engine.SetViewAngles(usercmd.viewangles)

	elseif method == "silent" then
		usercmd.viewangles = angle
	end
end

local function ShouldFire()
	local pLocal = entities.GetLocalPlayer()
	if not pLocal then return false end
	
	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
	if not pWeapon then return false end

	if not pWeapon:IsShootingWeapon() then return false end

	if not input.IsButtonDown(gui.GetValue("aim key")) then return false end
	if not pLocal:IsAlive() then return false end

	local iAmmo = pWeapon:GetPropInt("m_iClip1")
	if iAmmo == 0 then return false end

	if not input.IsButtonDown(gui.GetValue("aim key")) then return false end

	if gui.GetValue("aim when reloading") == 0 and pWeapon:GetPropInt("m_iReloadMode") > 0 then return false end

	return true
end

---@param usercmd UserCmd
local function Run(usercmd)
	local localplayer = entities.GetLocalPlayer()
	if not localplayer then return end

	local weapon = localplayer:GetPropEntity("m_hActiveWeapon")
	if not weapon then return end

	---@type Target
	local target = GetTarget(localplayer, weapon)

	local shouldAim = input.IsButtonDown(gui.GetValue("aim key")) and ((usercmd.buttons & IN_ATTACK) ~= 0)

	if shouldAim then
		if localplayer:GetPropInt("m_iClass") == TF2_Heavy and weapon:GetWeaponID() == E_WeaponBaseID.TF_WEAPON_MINIGUN and gui.GetValue("minigun spinup") == 1 then
			usercmd.buttons = usercmd.buttons | IN_ATTACK2
		end

		Aim(usercmd, target.vAngleTo:Unpack())
		
		if gui.GetValue("auto shoot") == 1 then
			usercmd.buttons = usercmd.buttons | IN_ATTACK
		end

	end
end

callbacks.Register("CreateMove", Run)