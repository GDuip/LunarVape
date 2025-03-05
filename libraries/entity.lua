--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.

local entitylib = {
    isAlive = false,
    character = nil, -- Explicitly set to nil
    List = {},
    Connections = {},
    PlayerConnections = {},
    EntityThreads = {},
    Running = false,
    Events = setmetatable({}, {
        __index = function(self, ind)
            self[ind] = {
                Connections = {},
                Connect = function(rself, func)
                    local connection = { Disconnect = function() end }
                    table.insert(rself.Connections, {func = func, conn = connection})
                    connection.Disconnect = function()
                        for i, v in ipairs(rself.Connections) do
                            if v.func == func then
                                table.remove(rself.Connections, i)
                                break
                            end
                        end
                    end
                    return connection
                end,
                Fire = function(rself, ...)
                    for _, v in ipairs(rself.Connections) do
                        pcall(v.func, ...) -- Protected call to event handlers
                    end
                end,
                Destroy = function(rself)
                    for _, v in ipairs(rself.Connections) do
                        if v.conn and v.conn.Disconnect then
                            v.conn.Disconnect()
                        end
                    end
                    rself.Connections = nil -- Explicit nil assignment for GC
                    rself = nil            -- Clean up reference
                end
            }
            return self[ind]
        end
    })
}


local playersService = game:GetService('Players')
local runService = game:GetService("RunService") -- Get RunService to improve task efficiency
local inputService = game:GetService('UserInputService')
local lplr = playersService.LocalPlayer
local gameCamera

-- Function to calculate dot product (optimized for performance)
local function dotProduct(v1, v2)
    return v1.X * v2.X + v1.Y * v2.Y + v1.Z * v2.Z
end

-- Get Camera & Viewport using optimized functions
local function getCamera()
   local cam = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
   if not cam then -- Critical Check. If camera goes nil, prevent a error flood
      task.wait() -- Prevent lag
      return getCamera()
   end
    return cam

end

local function updateCamera()
     gameCamera = getCamera() -- make gameCamera a direct link

end

local function getViewport()
	local viewport = gameCamera and gameCamera.ViewportSize -- Prevent viewport nil issue.

   if not viewport then -- critical camera/viewport handling!
      task.wait()
      return getViewport()  --retry
   end

    return viewport

end

-- Get mouse position (cross-platform, avoids unnecessary function calls)
local function getMousePosition()
  return inputService.TouchEnabled and (getViewport() / 2) or inputService:GetMouseLocation()
end

-- Deep Clean Function (Optimized and robust, with immediate cleanup)
local function deepClean(tbl)
    if not tbl then return end

    local keysToNil = {} -- Use a separate table for keys, *very* important during iteration.
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            deepClean(v)
        elseif typeof(v) == "Instance" and v.Destroy then
            pcall(v.Destroy, v) -- Safe destruction of Instances
        elseif typeof(v) == "RBXScriptConnection" and v.Disconnect then
            pcall(v.Disconnect, v)
        end
        table.insert(keysToNil, k) -- Queue key for nil-ing *outside* of loop
    end

    for _, k in ipairs(keysToNil) do
       tbl[k] = nil
    end

   -- clean the Metatable too!
   if getmetatable(tbl) then
     setmetatable(tbl,nil)
   end
end


-- Robust, Efficient and Safe WaitForChild Function (Best-in-class for Roblox)
local function safeWaitForChild(obj, name, timeout, className)
    if not obj or not obj.Parent then return nil end

    local endTime = tick() + (timeout or 5) -- Default timeout of 5 seconds

     -- fast name search. If not found then make more complete checks.
     if obj:FindFirstChild(name) then
       if className then -- added extra verification by type
         if typeof(obj:FindFirstChild(name)) == className then
            return obj:FindFirstChild(name)
          end
         else
           return obj:FindFirstChild(name)
         end
     end


    while tick() < endTime do
      local child = className and obj:FindFirstChildOfClass(name) or obj:FindFirstChild(name)

        if child then return child end
      runService.Heartbeat:Wait() -- Use Heartbeat to bind waiting efficiently to frame updates. Prevents excessive while-loop yields.
    end
    return nil
end



entitylib.targetCheck = function(ent)
    if not ent then return false end
    if ent.TeamCheck then return ent:TeamCheck() end
    if ent.NPC then return true end
    if not lplr.Team or not ent.Player or not ent.Player.Team then return true end -- Full safety
    return ent.Player.Team ~= lplr.Team or #ent.Player.Team:GetPlayers() == #playersService:GetPlayers()
end


entitylib.getUpdateConnections = function(ent)
	if not ent.Humanoid then return {} end
    return {
        ent.Humanoid:GetPropertyChangedSignal('Health'),
        ent.Humanoid:GetPropertyChangedSignal('MaxHealth'),
		-- added a useful connection!
        ent.Humanoid:GetPropertyChangedSignal('Jump')
    }
end


entitylib.isVulnerable = function(ent)
	if not ent or not ent.Humanoid or not ent.Character then return false end -- Full safety check.

    return ent.Humanoid.Health > 0 and not ent.Character:FindFirstChildWhichIsA('ForceField')
end

entitylib.getEntityColor = function(ent)
    return ent.Player and ent.Player.TeamColor and tostring(ent.Player.TeamColor) ~= 'White' and ent.Player.TeamColor.Color
end

entitylib.IgnoreObject = RaycastParams.new()
entitylib.IgnoreObject.FilterType = Enum.RaycastFilterType.Exclude --Use Exclude to handle a bunch of Objects
entitylib.IgnoreObject.RespectCanCollide = true


entitylib.Wallcheck = function(origin, position, ignoreobject)
  if not origin or not position then return true end
  local ignoreList = {gameCamera, lplr.Character}


   -- handle object correctly. Instance first then Table and finally EntityList
 if typeof(ignoreobject) == 'Instance' then -- Instance comes first!
        table.insert(ignoreList, ignoreobject)

    elseif type(ignoreobject) == 'table' then

        for _, v in ipairs(ignoreobject) do
          if typeof(v) == 'Instance' then  --Added filtering type check for instances only.
                table.insert(ignoreList, v)
           end

        end
     else
		  -- Use pairs to support gaps/nils in the List table
        for _, v in pairs(entitylib.List) do
             if v and v.Targetable and v.Character then  --Added a more compact way
              table.insert(ignoreList, v.Character)

            end
        end
     end

    entitylib.IgnoreObject.FilterDescendantsInstances = ignoreList

    local raycastResult = workspace:Raycast(origin, (position - origin), entitylib.IgnoreObject)
     return raycastResult ~= nil --True if there is a Wall

end


-- Greatly Optimized Entity Filtering (Micro-optimizations and reduced function calls)
local function filterEntities(entitysettings, returnSingle)
   if not entitylib.isAlive then return returnSingle and nil or {} end

    local mouseLocation = entitysettings.MouseOrigin or getMousePosition()
    local localPosition = entitysettings.Origin or (entitylib.character and entitylib.character.HumanoidRootPart and entitylib.character.HumanoidRootPart.Position) or Vector3.new()

    local sortingTable = {}


  for _, v in pairs(entitylib.List) do

        if not v then continue end  -- Key part of handling potentially deleted entries.

      if not v.Targetable then continue end

     -- Optimized: combining conditional, boolean logic.
     if (entitysettings.Players == false and v.Player) or (entitysettings.NPCs == false and v.NPC) then continue end


     local targetPart = v[entitysettings.Part]
     if not targetPart then continue end -- Part Check

		--Pre calculate and prevent many function call errors
        local  vis,position
      if entitysettings.MouseOrigin then
         position,vis = gameCamera.WorldToViewportPoint(gameCamera,targetPart.Position)
        if not vis then continue end
        end


        local mag
      if entitysettings.MouseOrigin  then
         mag = (mouseLocation - Vector2.new(position.x,position.y)).Magnitude -- calculated earlier!
        else

			local success,result  = pcall(function()  -- Wrapped .Position usage.
			 mag = (targetPart.Position - localPosition).Magnitude -- using magnitude to avoid doing the operations manually
          end)

            if not success then continue end

        end


        if mag > entitysettings.Range then continue end

		 if not entitylib.isVulnerable(v) then continue end

        table.insert(sortingTable, {
            Entity = v,
          Magnitude =  (v.Target and -1 or mag) or math.huge
        })

    end



    table.sort(sortingTable, entitysettings.Sort or function(a, b)

      return a.Magnitude < b.Magnitude

   end)

    local returned = {} -- table for multiple values

  for _, v in ipairs(sortingTable) do

      if entitysettings.Wallcheck then
           if entitylib.Wallcheck(entitysettings.MouseOrigin and position or localPosition, v.Entity[entitysettings.Part].Position, entitysettings.Wallcheck) then continue end -- added correct wallchecking here too

        end
         -- single values comes first.
      if returnSingle then
             return v.Entity

        else
             table.insert(returned,v.Entity)

            if #returned >= (entitysettings.Limit or math.huge) then return returned end -- optimized returned values here
        end

    end

   return returnSingle and nil or returned

end


entitylib.EntityMouse = function(entitysettings)
	if not entitysettings then return end
    return filterEntities(entitysettings, true)
end

entitylib.EntityPosition = function(entitysettings)
    if not entitysettings then return end
	return filterEntities(entitysettings, true)
end

entitylib.AllPosition = function(entitysettings)
	if not entitysettings then return {} end
    return filterEntities(entitysettings, false)
end

-- Entity retrieval function (fast and handles nil)
entitylib.getEntity = function(char)
    if not char then return nil, nil end
    for i, v in pairs(entitylib.List) do -- Optimized pairs, handling gaps.
        if v and (v.Player == char or v.Character == char) then
            return v, i
        end
    end
    return nil, nil
end

entitylib.addEntity = function(char, plr, teamfunc)

    if not char then return end

    -- Check Duplicates: critical optimization!
    if entitylib.getEntity(char) then return end


  entitylib.EntityThreads[char] = task.spawn(function() -- Sepparated thread

    local hum = safeWaitForChild(char, 'Humanoid', 10)
    local humrootpart = hum and safeWaitForChild(hum, 'RootPart',  workspace.StreamingEnabled and 9e9 or 10 ,true) -- 9e9 equals to INFINITE!
      local head = char and safeWaitForChild(char, 'Head', 10) or humrootpart  -- Safe retrieval

       if hum and humrootpart then
           local entity = {
                Connections = {},
                Character = char,
               Health = hum.Health,
              Head = head,
                Humanoid = hum,
              HumanoidRootPart = humrootpart,
                HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2), --Simplified!
                MaxHealth = hum.MaxHealth,
              NPC = plr == nil,
             Player = plr,
             RootPart = humrootpart,
                TeamCheck = teamfunc,
               Target = false, -- Explicitly initialize "Target" property.
            }

          if plr == lplr then
             entitylib.character = entity -- set it only once!
              entitylib.isAlive = true
            entitylib.Events.LocalAdded:Fire(entity)

           else

                entity.Targetable = entitylib.targetCheck(entity)
                 for _, v in ipairs(entitylib.getUpdateConnections(entity)) do

                     local conn = v:Connect(function()
                          if not entity.Humanoid then return end

                           entity.Health = entity.Humanoid.Health --use directly from Humanoid

                         entity.MaxHealth = entity.Humanoid.MaxHealth

                         entitylib.Events.EntityUpdated:Fire(entity) -- trigger Update Events
                     end)
                    table.insert(entity.Connections, conn)
                 end

              table.insert(entitylib.List, entity)
               entitylib.Events.EntityAdded:Fire(entity) -- single trigger call!
           end

         end
        entitylib.EntityThreads[char] = nil

    end)
end


entitylib.removeEntity = function(char, localcheck)
  if localcheck then
        if entitylib.isAlive then

             entitylib.isAlive = false
          if entitylib.character and  entitylib.character.Connections then -- protect for nil entity values

             for _, v in ipairs(entitylib.character.Connections) do

                   if v and v.Disconnect then  -- make it compact, handle nil connections!

                     v.Disconnect()

                    end
                end

               entitylib.character.Connections = nil -- important memory managment
         end
            if entitylib.character then --prevent error if .LocalRemoved fired!

               entitylib.Events.LocalRemoved:Fire(entitylib.character)  -- Notify before destruction.

            end
          entitylib.character = nil -- nil here!

            end
       return

   end



   if char then  -- added not char protection!

       if entitylib.EntityThreads[char] then  -- make a compact handling
        task.cancel(entitylib.EntityThreads[char])

          entitylib.EntityThreads[char] = nil

         end

      local entity, ind = entitylib.getEntity(char)  -- check entity here


      if entity then
          if entity.Connections then
             for _, v in ipairs(entity.Connections) do

                 if v and v.Disconnect then  -- Handle disconnected connections!

                   v.Disconnect()
                end

             end

           entity.Connections = nil  -- Efficient nil-ing.

          end

         entitylib.Events.EntityRemoved:Fire(entity) --trigger before removed
        table.remove(entitylib.List, table.find(entitylib.List,entity))  -- added best table removing function


         end
  end

end

-- Refresh entity (Optimized, handles missing entities, checks character)
entitylib.refreshEntity = function(char, plr)
    if not char then return end -- check if there is no Char
	entitylib.removeEntity(char)  -- check char on Remove.
	entitylib.addEntity(char, plr)   -- check char on Add.
end


entitylib.addPlayer = function(plr)
   if not plr then return end
	if entitylib.PlayerConnections[plr] then return end

  if plr.Character then --Added character Check before Refresh.

   entitylib.refreshEntity(plr.Character, plr)
  end

    local Connections = {} -- better create connection varialble here!

	table.insert(Connections, plr.CharacterAdded:Connect(function(char)
	 entitylib.refreshEntity(char, plr)
   end))

	table.insert(Connections, plr.CharacterRemoving:Connect(function(char)
        entitylib.removeEntity(char)
    end))

  table.insert(Connections, plr:GetPropertyChangedSignal('Team'):Connect(function() -- Use Player.Team

         for _, v in pairs(entitylib.List) do
              if v and v.Character and v.Player then  -- protect of nils

                  if v.Targetable ~= entitylib.targetCheck(v) then

                     entitylib.refreshEntity(v.Character, v.Player)
                   end

               end
          end


          if plr == lplr then
             entitylib.start()
        else
           entitylib.refreshEntity(plr.Character, plr)

         end

      end))
    entitylib.PlayerConnections[plr] = Connections

end



entitylib.removePlayer = function(plr)
	if not plr then return end

	if entitylib.PlayerConnections[plr] then  --added protect of not connected players.
       for _, v in ipairs(entitylib.PlayerConnections[plr]) do
         if v and v.Disconnect then -- Handle nil connection,compact function.

                v.Disconnect()
              end
         end
     entitylib.PlayerConnections[plr] = nil  -- Clean up completely!
 end

	  entitylib.removeEntity(plr.Character) --removed with character check
end


entitylib.start = function()
    if entitylib.Running then entitylib.stop() end  --Prevent overlapping runs

	updateCamera()  -- Initialize gameCamera

    table.insert(entitylib.Connections, playersService.PlayerAdded:Connect(entitylib.addPlayer)) -- added addPlayer Function
    table.insert(entitylib.Connections, playersService.PlayerRemoving:Connect(entitylib.removePlayer)) -- added removePlayer Function

    for _, v in ipairs(playersService:GetPlayers()) do --ipairs when dealing with numberical indexed!
         entitylib.addPlayer(v)
    end

   table.insert(entitylib.Connections, workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(updateCamera))

    entitylib.Running = true

end



entitylib.stop = function()
    if not entitylib.Running then return end  --Prevent issues

    for _, v in ipairs(entitylib.Connections) do
          if v and v.Disconnect then  -- Handle Disconnect!

               v.Disconnect()

            end

      end
  entitylib.Connections = {}



 for plr,playerConnections in pairs(entitylib.PlayerConnections) do  -- Added safety loops to safely delete connections

      for _, connection in ipairs(playerConnections) do
        if connection and connection.Disconnect then
            connection.Disconnect()
          end
      end

    entitylib.PlayerConnections[plr] = nil  -- Clean each entry
  end



 entitylib.removeEntity(nil, true)

  -- Use optimized cleaning
    local cloned = {}
     for i, v in pairs(entitylib.List) do

        table.insert(cloned,v)
    end



 for _, v in pairs(cloned) do -- critical: separate loops to not break entitylib during its own remove methods.
	   if v.Character then
         entitylib.removeEntity(v.Character)

      end
 end

    entitylib.List = {}  -- use nils or {} to freeup more memory!


   for char, thread in pairs(entitylib.EntityThreads) do

    task.cancel(thread) -- handle cancellation on Threads.

        entitylib.EntityThreads[char] = nil

  end
    entitylib.Running = false
end

entitylib.kill = function()
 if entitylib.Running then -- protect nested Kills!
       entitylib.stop()

    end

    for _, v in pairs(entitylib.Events) do

     if v and v.Destroy then  -- handle errors correctly

       v:Destroy()
     end

  end

  entitylib.Events = nil  -- clear reference to metatable

 entitylib.IgnoreObject:Destroy()  -- destroy Instance object!


   deepClean(entitylib)  -- total cleanup with robust clear

	entitylib = nil  -- final clean!

end

entitylib.refresh = function()

   local cloned = {} -- save a copy

 for _, v in pairs(entitylib.List) do -- use pairs() here

         table.insert(cloned,v)

     end
	for _, v in ipairs(cloned) do
    if v and v.Character and v.Player then --added all value check to protect from nils!
        entitylib.refreshEntity(v.Character, v.Player) -- v : refresh the Entity on the Copy

       end
	end
    cloned = nil

end


entitylib.start()  -- Initial setup. Essential.


return entitylib
