--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.
--[[
	Prediction Library
	Source: https://devforum.roblox.com/t/predict-projectile-ballistics-including-gravity-and-motion/1842434
]]

local module = {}

-- Constants (Pre-calculated for efficiency)
local ONE_THIRD = 1 / 3
local TWO_THIRDS_PI = 2 * math.pi / 3
local PI_OVER_THREE = math.pi / 3
local PREDICTION_SMOOTHING_FACTOR = 0.25
local MAX_PREDICTION_TIME = 0.8
local GRAVITY_ADJUSTMENT_ITERATIONS = 7  -- Increased for maximum accuracy within reason
local TARGET_HISTORY_LENGTH = 14        -- Keep more history for better averaging
local VELOCITY_AVERAGING_SAMPLES = 7     -- Further balance of smoothness
local MIN_VELOCITY_MAGNITUDE = 0.01
local EPSILON = 1e-7                    -- Stricter floating-point comparisons

-- Pre-allocate tables to avoid garbage collection
local reusableSolutions = {}
local reusableCoeffs = {}

--[[
    Numerical Solver Functions (Cubic and Quartic Equation Solvers)
    Highly optimized with early exits and pre-calculated constants.
]]

local function isZero(d)
	return (d > -EPSILON and d < EPSILON)
end

local function cuberoot(x)
	return (x > 0) and math.pow(x, ONE_THIRD) or -math.pow(math.abs(x), ONE_THIRD)
end

local function solveQuadric(c0, c1, c2, outSolutions)
	local p = c1 / (2 * c0)
	local q = c2 / c0
	local D = p * p - q

	if isZero(D) then
		outSolutions[1] = -p
        outSolutions[2] = nil  -- Clear
		return 1
	elseif D > 0 then
		local sqrt_D = math.sqrt(D)
		outSolutions[1] = sqrt_D - p
		outSolutions[2] = -sqrt_D - p
		return 2
	end
     outSolutions[1] = nil  -- Clear
     outSolutions[2] = nil
	return 0
end

local function solveCubic(c0, c1, c2, c3, outSolutions)
    local num = 0
    local A = c1 / c0
    local B = c2 / c0
    local C = c3 / c0

    local sq_A = A * A
    local p = ONE_THIRD * (-ONE_THIRD * sq_A + B)
    local q = 0.5 * ((2 / 27) * A * sq_A - ONE_THIRD * A * B + C)

    local cb_p = p * p * p
    local D = q * q + cb_p

    if isZero(D) then
        if isZero(q) then
            outSolutions[1] = 0
            num = 1
        else
            local u = cuberoot(-q)
            outSolutions[1] = 2 * u
            outSolutions[2] = -u
            num = 2
        end
    elseif D < 0 then
        local phi = ONE_THIRD * math.acos(-q / math.sqrt(-cb_p))
        local t = 2 * math.sqrt(-p)
        outSolutions[1] = t * math.cos(phi)
        outSolutions[2] = -t * math.cos(phi + PI_OVER_THREE)
        outSolutions[3] = -t * math.cos(phi - PI_OVER_THREE)
        num = 3
    else
        local sqrt_D = math.sqrt(D)
        local u = cuberoot(sqrt_D - q)
        local v = -cuberoot(sqrt_D + q)
        outSolutions[1] = u + v
        num = 1
    end

    local sub = ONE_THIRD * A
    if num > 0 then outSolutions[1] = outSolutions[1] - sub end
    if num > 1 then outSolutions[2] = outSolutions[2] - sub end
    if num > 2 then outSolutions[3] = outSolutions[3] - sub end
    outSolutions[4] = nil --Clear

    return num, outSolutions
end

function module.solveQuartic(c0, c1, c2, c3, c4)
    local coeffs = reusableCoeffs
	local s0, s1, s2, s3

	local A = c1 / c0
	local B = c2 / c0
	local C = c3 / c0
	local D = c4 / c0

	local sq_A = A * A
	local p = -0.375 * sq_A + B
	local q = 0.125 * sq_A * A - 0.5 * A * B + C
	local r = -0.01171875 * sq_A * sq_A + 0.0625 * sq_A * B - 0.25 * A * C + D

	if isZero(r) then
		coeffs[3] = q
		coeffs[2] = p
		coeffs[1] = 0
		coeffs[0] = 1
		local _, cubicSolutions = solveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3], reusableSolutions)
        local num = 0
        -- Copy Solutions
        if cubicSolutions[1] ~= nil then s0 = cubicSolutions[1]; num = num + 1 end
        if cubicSolutions[2] ~= nil then s1 = cubicSolutions[2]; num = num + 1 end
        if cubicSolutions[3] ~= nil then s2 = cubicSolutions[3]; num = num + 1 end

        local sub = 0.25 * A
        if num > 0 then s0 = s0 - sub end
        if num > 1 then s1 = s1 - sub end
        if num > 2 then s2 = s2 - sub end
         return {s0, s1, s2} -- Always a table
	else
		coeffs[3] = 0.5 * r * p - 0.125 * q * q
		coeffs[2] = -r
		coeffs[1] = -0.5 * p
		coeffs[0] = 1

		local _, cubicSolutions = solveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3], reusableSolutions)
		local z = cubicSolutions[1]

		local u = z * z - r
		local v = 2 * z - p

        if u < 0 or v < 0 then  return {} end -- No valid solutions

		if isZero(u) then u = 0 else u = math.sqrt(u) end
		if isZero(v) then v = 0 else v = math.sqrt(v) end

		coeffs[2] = z - u
		coeffs[1] = q < 0 and -v or v
		coeffs[0] = 1

        local num, quadSolutions1 = solveQuadric(coeffs[0], coeffs[1], coeffs[2], reusableSolutions)
        s0, s1 = quadSolutions1[1], quadSolutions1[2]

        if num == 2 then
           local sub = 0.25 * A
            if s0 ~= nil then s0 = s0 - sub end
            if s1 ~= nil then s1 = s1 - sub end
            return {s0, s1}  -- Early exit
        end

		coeffs[2] = z + u
		coeffs[1] = q < 0 and v or -v
		coeffs[0] = 1

        local _, quadSolutions2 = solveQuadric(coeffs[0], coeffs[1], coeffs[2], reusableSolutions)
        s2, s3 = quadSolutions2[1], quadSolutions2[2]

        local combinedSolutions = {}
        local count = 0
        if s0 ~= nil then count = count + 1; combinedSolutions[count] = s0 end
        if s1 ~= nil then count = count + 1; combinedSolutions[count] = s1 end
        if s2 ~= nil then count = count + 1; combinedSolutions[count] = s2 end
        if s3 ~= nil then count = count + 1; combinedSolutions[count] = s3 end

        local sub = 0.25 * A
        for i = 1, count do
            combinedSolutions[i] = combinedSolutions[i] - sub
        end
        return combinedSolutions
	end
end

--[[
    Target Prediction Functions
    Highly refined, using a longer history and more sophisticated averaging.
]]

local targetHistory = {}
local lastValidVelocity = Vector3.zero
local lastPosition = Vector3.zero
local lastUpdateTime = 0
local smoothedVelocity = Vector3.zero -- Store the fully smoothed velocity

local function calculateAverageVelocity()
    if #targetHistory < VELOCITY_AVERAGING_SAMPLES then
        return lastValidVelocity
    end

    local totalVelocity = Vector3.zero
    local validSamples = 0
    local weightedTotalVelocity = Vector3.zero
    local totalWeight = 0

    -- Weighted Averaging:  Give more weight to recent samples.
    for i = #targetHistory, math.max(1, #targetHistory - VELOCITY_AVERAGING_SAMPLES + 1), -1 do
        local current = targetHistory[i]
        local previous = targetHistory[i - 1]

        if previous and current.time > previous.time then
            local deltaTime = current.time - previous.time
            local velocity = (current.position - previous.position) / deltaTime

            -- Exponential weighting:  Weight = 0.8^(age)
            local age = #targetHistory - i
            local weight = math.pow(0.8, age)

            weightedTotalVelocity = weightedTotalVelocity + velocity * weight
            totalWeight = totalWeight + weight
            validSamples = validSamples + 1
        end
    end
     -- Return either weighted average or if not, lastValidVelocity
    return (validSamples > 0 and totalWeight > 0) and weightedTotalVelocity / totalWeight or lastValidVelocity
end

local function exponentialSmoothing(newValue, oldValue, alpha)
	return alpha * newValue + (1 - alpha) * oldValue
end

local function predictTargetPosition(targetPos, deltaTime)
	local currentTime = os.clock()
	local deltaTimeSinceLastUpdate = currentTime - lastUpdateTime

    table.insert(targetHistory, {position = targetPos, time = currentTime})
    if #targetHistory > TARGET_HISTORY_LENGTH then
        table.remove(targetHistory, 1)
    end

    local currentVelocity
    if deltaTimeSinceLastUpdate > 0 then
        currentVelocity = (targetPos - lastPosition) / deltaTimeSinceLastUpdate
        lastValidVelocity = currentVelocity
    else
        currentVelocity = lastValidVelocity  -- Use last *valid*
    end

    local averageVelocity = calculateAverageVelocity()
	-- Smooth the average velocity using the stored smoothed velocity.
    smoothedVelocity = exponentialSmoothing(averageVelocity, smoothedVelocity, PREDICTION_SMOOTHING_FACTOR)

    local predictedPosition = targetPos + smoothedVelocity * deltaTime

    lastPosition = targetPos
    lastUpdateTime = currentTime

    return predictedPosition
end

--[[
	Optimized Raycasting Functions
]]

--[[
--Cast Raycast from currentPos and return the intersection Point
--]]
local function raycastOptimized(currentPos, direction, params)
	local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist -- Use Blacklist for best performance
    raycastParams.FilterDescendantsInstances = params.Ignore or {}
    raycastParams.IgnoreWater = true -- Optimize unless you specifically need to detect water
	raycastParams.RespectCanCollide = true
	
    local ray = workspace:Raycast(currentPos, direction, raycastParams)  -- Use workspace:Raycast
    return ray
end

--[[
    Trajectory Solution Function - with greatly enhanced raycasting and logic.
]]

function module.SolveTrajectory(origin, projectileSpeed, gravity, targetPos, targetVelocity, playerGravity, playerHeight, playerJump, params)
	local disp = targetPos - origin
	local p, q, r = targetVelocity.X, targetVelocity.Y, targetVelocity.Z
	local h, j, k = disp.X, disp.Y, disp.Z
	local l = -.5 * gravity

    -- Zero gravity check (early exit)
	if gravity == 0 then
		local t = disp.Magnitude / projectileSpeed
		local d = (h + p*t) / t
		local e = (j + q*t) / t
		local f = (k + r*t) / t
		return origin + Vector3.new(d, e, f)
	end

    -- 1. Initial Prediction (Use refined velocity projection)
	local targetVelocityTowardsShooter = disp:Dot(targetVelocity) / disp.Magnitude
	local estimatedTravelTime = disp.Magnitude / (projectileSpeed + targetVelocityTowardsShooter)
	local deltaTime = math.min(estimatedTravelTime, MAX_PREDICTION_TIME)
	local predictedTargetPos = predictTargetPosition(targetPos, deltaTime)
    disp = predictedTargetPos - origin  -- Update disp
	h, j, k = disp.X, disp.Y, disp.Z

	-- 2. Iterative Gravity Adjustment with Optimized Raycasting
	if playerGravity and playerGravity > EPSILON then
		local estTime = disp.Magnitude / projectileSpeed -- Initial best time
		local origq = q
		local origj = j
		local currentTargetPos = predictedTargetPos
        local hasHit = false

		for i = 1, GRAVITY_ADJUSTMENT_ITERATIONS do
            -- The critical velocity adjustment, incorporating *both* target velocity and gravity.
			local adjustedTargetVelocityY = origq - (0.5 * playerGravity * estTime)

			-- Ray direction: Considers *predicted* horizontal movement *and* gravity-adjusted vertical movement
            local velo = targetVelocity * 0.016
			local rayDirection = Vector3.new(velo.X * estTime, adjustedTargetVelocityY * estTime - playerHeight, velo.Z * estTime)
			
			local ray = raycastOptimized(currentTargetPos, rayDirection, params)

            if ray then
                hasHit = true
                local newTarget = ray.Position + Vector3.new(0,playerHeight, 0)
                local distanceToNewTarget = (currentTargetPos - newTarget).Magnitude

                -- Key improvement: Refine estTime based on ACTUAL vertical displacement due to gravity.
				estTime = estTime - (math.sqrt((2 * distanceToNewTarget) / math.abs(playerGravity)))

                currentTargetPos = newTarget  -- Move target to hit position
				j = (currentTargetPos - origin).Y  -- Recalculate vertical displacement
			else
				break  -- No hit, stop iterating.  This is important!
			end
		end
		disp = currentTargetPos - origin  -- Update disp
		h, j, k = disp.X, disp.Y, disp.Z
		q = origq - (0.5 * playerGravity * estTime) --Final q
	end


    -- 3. Solve the Quartic Equation (only after gravity adjustments)
	local solutions = module.solveQuartic(
		l*l,
		-2*q*l,
		q*q - 2*j*l - projectileSpeed*projectileSpeed + p*p + r*r,
		2*j*q + 2*h*p + 2*k*r,
		j*j + h*h + k*k
	)
	
    -- 4. Find Best Solution (with more robust checking)
    if solutions then
		local bestSolution = nil
		local bestTime = math.huge

        for _, time in ipairs(solutions) do
            if time > EPSILON then
                local d = (h + p*time) / time
				local e = (j + q*time - l*time*time) / time
				local f = (k + r*time) / time

                local trajectoryPoint = origin + Vector3.new(d,e,f)

                 --Check if this is a better solution
                if time < bestTime then
                    bestTime = time
                    bestSolution = trajectoryPoint
                end
            end
        end
         return bestSolution  -- Can be nil
    end
    return nil
end

return module
