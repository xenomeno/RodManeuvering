dofile("Bitmap.lua")
dofile("Geometry.lua")

local RBTree = dofile("RBTree.lua")

local IMAGE_SIZE      = 720
local OBSTACLES_SCALE = 1.8       -- scale 1.0 corresponds to IMAGE_SIZE = 400
local WRITE_FRAMES    = false      -- set to true to draw BMP images during processing

local ROD_WIDTH       = math.floor(3 * OBSTACLES_SCALE)
local ROD_LENGTH      = math.floor(120 * OBSTACLES_SCALE)
local PI              = math.pi
local DEG_10          = PI / 18
local DEG_90          = PI / 2
local DEG_180         = PI

local MOVE_DIST_FRACT = 20
local MOVE_DIST       = IMAGE_SIZE / MOVE_DIST_FRACT
local ROTATE_STEP_DEG = 10      -- NOTE: must be divider of 360
local ROTATE_STEPS    = 360 // ROTATE_STEP_DEG
local ROTATE_STEP_RAD = ROTATE_STEP_DEG * PI / 180
local MOVES_LAYER     = MOVE_DIST_FRACT * MOVE_DIST_FRACT
local STATES          = MOVES_LAYER * ROTATE_STEPS

local FORWARD         = 1
local BACKWARD        = 2
local CLOCKWISE       = 3
local ANTI_CLOCKWISE  = 4
local LEFT            = 5
local RIGHT           = 6
local ACTIONS         = { FORWARD, BACKWARD, CLOCKWISE, ANTI_CLOCKWISE }
--local ACTIONS         = { FORWARD, BACKWARD, CLOCKWISE, ANTI_CLOCKWISE, LEFT, RIGHT }

-- polygons should be clockwise
local s_Obstacles =
{
  { { x = 98, y = 21 }, { x = 113, y = 69 }, { x = 77, y = 103 }, { x = 63, y = 56 } },
  { { x = 33, y = 120 }, { x = 96, y = 135 }, { x = 150, y = 170 }, { x = 88, y = 155 }, },
  { { x = 191, y = 66 }, { x = 235, y = 74 }, { x = 252, y = 116 }, { x = 207, y = 108 } },
  { { x = 322, y = 8 }, { x = 367, y = 29 }, { x = 388, y = 72 }, { x = 343, y = 52 } },
  { { x = 288, y = 96 }, { x = 312, y = 179 }, { x = 298, y = 262 }, { x = 274, y = 181 } },
  { { x = 86, y = 185 }, { x = 157, y = 239 }, { x = 152, y = 326 }, { x = 80, y = 275 } },
  { { x = 272, y = 287 }, { x = 301, y = 312 }, { x = 304, y = 352 }, { x = 275, y = 325 } },
  { { x = 336, y = 336 }, { x = 381, y = 348 }, { x = 342, y = 374 }, { x = 297, y = 362 } },
  Start = { x = 53, y = 273, angle = DEG_180 - DEG_10 },
  Goal = { x = 336, y = 126, angle = DEG_10 },
}

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	else
		return x
	end
end

function table.find(array, field, value)
	if not array then return end
	if value == nil then
		value = field
		for i = 1, #array do
			if value == array[i] then return i end
		end
	else
		for i = 1, #array do
			if value == array[i][field] then return i end
		end
	end
end

function table.max(t, functor)
	local max, max_i
	if functor then
		local max_value
		for i = 1, #t do
			local value = functor(t[i])
			if value and (not max_value or value > max_value) then
				max, max_value, max_i = t[i], value, i
			end
		end
	else
		max, max_i = t[1], 1
		for i = 2, #t do
			local value = t[i]
			if value > max then
				max, max_i = value, i
			end
		end
	end
	return max, max_i
end

local s_Sin, s_Cos = {}, {}

local function RotatePoint(x, y, angle)
  s_Sin[angle] = s_Sin[angle] or math.sin(angle)
  s_Cos[angle] = s_Cos[angle] or math.cos(angle)
  
  local sin = s_Sin[angle]
  local cos = s_Cos[angle]  
	local rx = x * cos - y * sin
	local ry = x * sin + y * cos
  
  return rx, ry
end

local function GetRotatedBoxVertices(x1, y1, x2, y2, angle)
  local x = (x1 + x2) / 2
  local y = (y1 + y2) / 2
  local u1, v1 = RotatePoint(x1 - x, y1 - y, angle)
  local u2, v2 = RotatePoint(x2 - x, y1 - y, angle)
  local u3, v3 = RotatePoint(x2 - x, y2 - y, angle)
  local u4, v4 = RotatePoint(x1 - x, y2 - y, angle)
  
  return { {x = x+u1, y = y+v1}, {x = x+u2, y = y+v2}, {x = x+u3, y = y+v3}, {x = x+u4, y = y+v4} }
end

local function DrawRotatedBox(bmp, x1, y1, x2, y2, angle, color)
  local verts = GetRotatedBoxVertices(x1, y1, x2, y2, angle)
  local last = verts[#verts]
  local last_x, last_y = math.floor(last.x), math.floor(last.y)
  for _, v in ipairs(verts) do
    local v_x, v_y = math.floor(v.x), math.floor(v.y)
    bmp:DrawLine(last_x, last_y, v_x, v_y, color)
    last_x, last_y = v_x, v_y
  end
end

local function GetRodDirs(x, y, angle)
  local dir_x, dir_y = RotatePoint(0, -MOVE_DIST, angle)
  local pdir_x, pdir_y = RotatePoint(dir_x, dir_y, -PI / 2)
  
  return dir_x, dir_y, pdir_x, pdir_y
end

local function GetRodVertices(x, y, angle)
  return GetRotatedBoxVertices(x - ROD_WIDTH / 2, y - ROD_LENGTH / 2, x + ROD_WIDTH / 2, y + ROD_LENGTH / 2, angle)
end

local function DrawRod(bmp, pos_x, pos_y, angle, color, color_lookat)
  DrawRotatedBox(bmp, pos_x - ROD_WIDTH / 2, pos_y - ROD_LENGTH / 2, pos_x + ROD_WIDTH / 2, pos_y + ROD_LENGTH / 2, angle, color)
  local box_size = ROD_WIDTH / 2 + 2
  local dir_x, dir_y = GetRodDirs(pos_x, pos_y, angle)
  dir_x, dir_y = SetLen(dir_x, dir_y, ROD_LENGTH / 2, "int")
  local lookat_x, lookat_y = pos_x + dir_x, pos_y + dir_y
  DrawRotatedBox(bmp, lookat_x - box_size, lookat_y - box_size, lookat_x + box_size, lookat_y + box_size, angle, color_lookat)
end

local function SegCrossObstacle(x1, y1, x2, y2, obstacle)
  if PtInConvexPoly2D(x1, y1, obstacle) or PtInConvexPoly2D(x2, y2, obstacle) then
    return true
  end
  for i = 1, #obstacle - 1 do
    if SegInterSeg2D(x1, y1, x2, y2, obstacle[i].x, obstacle[i].y, obstacle[i + 1].x, obstacle[i + 1].y) then
      return true
    end
  end
end

local function SegCollides(x1, y1, x2, y2)
  if x1 < 0 or x1 >= IMAGE_SIZE or y1 < 0 or y1 >= IMAGE_SIZE then return true end
  if x2 < 0 or x2 >= IMAGE_SIZE or y2 < 0 or y2 >= IMAGE_SIZE then return true end
  
  for _, obstacle in ipairs(s_Obstacles) do
    if SegCrossObstacle(x1, y1, x2, y2, obstacle) then
      return true
    end
  end
end

local function RodCollides(x, y, angle)
  for _, obstacle in ipairs(s_Obstacles) do
    if PtInConvexPoly2D(x, y, obstacle) then
      return true
    end
  end
  
  local verts = GetRodVertices(x, y, angle)
  table.insert(verts, verts[1])
  for v = 1, #verts - 1 do
    if SegCollides(verts[v].x, verts[v].y, verts[v + 1].x, verts[v + 1].y) then
      return true
    end
  end
end

local function PosAngleRealToIdx(x, y, angle)
  return x // MOVE_DIST, y // MOVE_DIST, math.floor(angle / ROTATE_STEP_RAD + 0.0001)
end

local function PosAngleIdxToReal(x_idx, y_idx, angle_idx)
  return x_idx * MOVE_DIST + MOVE_DIST / 2, y_idx * MOVE_DIST + MOVE_DIST / 2, angle_idx * ROTATE_STEP_RAD
end

local function PosAngleIdxToState(x, y, angle)
  return 1 + y * MOVE_DIST_FRACT + x + MOVES_LAYER * angle
end

local function PosAngleRealToState(x, y, angle)
  local x_idx, y_idx, angle_idx = PosAngleRealToIdx(x, y, angle)
  
  return PosAngleIdxToState(x_idx, y_idx, angle_idx)
end

local function StateToPosAngleIdx(s)
  s = s - 1
  local angle = s // MOVES_LAYER
  s = s - angle * MOVES_LAYER
  local y = s // MOVE_DIST_FRACT
  local x = s - y * MOVE_DIST_FRACT
  
  return x, y, angle
end

local function StateToPosAngleReal(s)
  local x_idx, y_idx, angle_idx = StateToPosAngleIdx(s)
  
  return PosAngleIdxToReal(x_idx, y_idx, angle_idx)
end

local function ClampAngle(angle)
  if angle < 0 then
    angle = angle + 2 * PI
  elseif angle >= 2 * PI then
    angle = angle - 2 * PI
  end
  
  return angle
end

local function RegisterStateAction(Model, s, a, r, next_s)
  local record = Model[s][a]
  if record then
    record.r, record.next_s = r, next_s
    return
  end
  
  Model[s][a] = { r = r, next_s = next_s }
  if not Model.observed_states.marked[s] then
    Model.observed_states.marked[s] = true
    table.insert(Model.observed_states, s)
    Model.observed_state_actions[s] = { marked = {} }
  end
  local s_actions = Model.observed_state_actions[s]
  if not s_actions.marked[a] then
    s_actions.marked[a] = true
    table.insert(s_actions, a)
  end
end

local function GetMaxActions(Qs, threshold)
    local treshold = 0.001
    
    local max_actions, max_q = { 1 }, Qs[1]
    for a = 2, #Qs do
        local v = Qs[a]
        if math.abs(v - max_q) < treshold then
          table.insert(max_actions, a)
        elseif v > max_q then
          max_actions = { a }
          max_q = v
        end
    end
    
    return max_actions
end

local function TakeEpsilonGreedyAction(s, Q, epsilon)
  local avail_actions = (math.random() < 1.0 - epsilon) and GetMaxActions(Q[s]) or ACTIONS
  
  return avail_actions[math.random(1, #avail_actions)]
end

local function NextCell(x, y, move_x, move_y)
  if move_x >= 0.0 then
    if move_y <= 0.0 then
      if move_x > -move_y then
        x = x + MOVE_DIST
      else
        y = y - MOVE_DIST
      end
    else
      if move_x > move_y then
        x = x + MOVE_DIST
      else
        y = y + MOVE_DIST
      end
    end
  else 
    if move_y <= 0.0 then
      if -move_x > -move_y then
        x = x - MOVE_DIST
      else
        y = y - MOVE_DIST
      end
    else
      if -move_x > move_y then
        x = x - MOVE_DIST
      else
        y = y + MOVE_DIST
      end
    end
  end
  
  return clamp(x, 0, IMAGE_SIZE - 1), clamp(y, 0, IMAGE_SIZE - 1)
end

local function TakeAction(s, a)
    local x_idx, y_idx, angle_idx = StateToPosAngleIdx(s)
    local x, y, angle = PosAngleIdxToReal(x_idx, y_idx, angle_idx)
    local move_x, move_y
    if a == CLOCKWISE or a == ANTI_CLOCKWISE then
      angle = ClampAngle(angle + ((a == CLOCKWISE) and ROTATE_STEP_RAD or -ROTATE_STEP_RAD))
    else
      local dir_x, dir_y, pdir_x, pdir_y = GetRodDirs(x, y, angle)
      if a == FORWARD then
        move_x, move_y = dir_x, dir_y
      elseif a == BACKWARD then
        move_x, move_y = -dir_x, -dir_y
      elseif a == LEFT then
        move_x, move_y = pdir_x, pdir_y
      elseif a == RIGHT then
        move_x, move_y = -pdir_x, -pdir_y
      end
      x, y = NextCell(x, y, move_x, move_y)
    end
    x_idx, y_idx, angle_idx = PosAngleRealToIdx(x, y, angle)
    x, y, angle = PosAngleIdxToReal(x_idx, y_idx, angle_idx)
    local next_s = s
    local collides = RodCollides(x, y, angle)
    if not collides then
      next_s = PosAngleIdxToState(x_idx, y_idx, angle_idx)
    end
    
    return next_s, move_x, move_y, collides, PosAngleIdxToState(x_idx, y_idx, angle_idx)
end

local function CheckPriority(PQueue, Q, s, a, r, next_s, gamma)
    local max_Qa = table.max(Q[next_s])
    local priority = math.abs(r + gamma * max_Qa - Q[s][a])
    if priority > PQueue.treshold then
      PQueue:insert({key = priority, s = s, a = a})
    end
end

local function AddPrevStateAction(x, y, angle, dir_x, dir_y, angle_step, prev_action, prev_sa)
    local prev_x = clamp(x + dir_x, 0, IMAGE_SIZE - 1)
    local prev_y = clamp(y + dir_y, 0, IMAGE_SIZE - 1)
    local prev_angle = ClampAngle(angle + angle_step)
    
    if not RodCollides(prev_x, prev_y, prev_angle) then
      table.insert(prev_sa, { s = PosAngleRealToState(prev_x, prev_y, prev_angle), a = prev_action })
    end
end

local s_BlockingState = false
local s_NextState, s_PrevStateAction = false, false
local s_MaxClockTime = 300.0      -- 5 minutes

local function InitStateTransitions()
  local time = os.clock()
  
  -- first find blocking states - the ones where the rod can't go out from
  local blocking_state = {}
  local count = 0
  for s = 1, STATES do
    local x, y, angle = StateToPosAngleReal(s)
    local blocking = true
    if not RodCollides(x, y, angle) then
      for _, a in ipairs(ACTIONS) do
        if TakeAction(s, a) ~= s then
          blocking = false
          break
        end
      end
    end
    if blocking then
      blocking_state[s] = true
      count = count + 1
    end
  end
  
  -- now precalculate all possible transitions for every state
  local next_state = {}
  for s = 1, STATES do
    next_state[s] = {}
    if not blocking_state[s] then
      for _, a in ipairs(ACTIONS) do
        next_state[s][a] = TakeAction(s, a)
      end
    end
  end
  
  -- then precalculated all previous <prev_state, prev_action> pairs leading to a given state
  local using_left = table.find(ACTIONS, LEFT)
  local using_right = table.find(ACTIONS, RIGHT)
  local prev_state = {}
  for s = 1, STATES do
    prev_state[s] = {}
    if not blocking_state[s] then
      local x_idx, y_idx, angle_idx = StateToPosAngleIdx(s)
      local x, y, angle = PosAngleIdxToReal(x_idx, y_idx, angle_idx)
      local dir_x, dir_y, pdir_x, pdir_y = GetRodDirs(x, y, angle)
      local prev_sa = {}
      AddPrevStateAction(x, y, angle, -dir_x, -dir_y, 0, FORWARD, prev_sa)
      AddPrevStateAction(x, y, angle, dir_x, dir_y, 0, BACKWARD, prev_sa)
      AddPrevStateAction(x, y, angle, 0, 0, -ROTATE_STEP_RAD, CLOCKWISE, prev_sa)
      AddPrevStateAction(x, y, angle, 0, 0, ROTATE_STEP_RAD, ANTI_CLOCKWISE, prev_sa)
      if using_right then
        AddPrevStateAction(x, y, angle, -pdir_x, -pdir_y, 0, RIGHT, prev_sa)
      end
      if using_left then
        AddPrevStateAction(x, y, angle, pdir_x, pdir_y, 0, LEFT, prev_sa)
      end
    end
  end
  
  time = os.clock() - time
  print(string.format("Blocking states & transition precalculation time: %ss", time))
  
  s_BlockingState = blocking_state
  s_NextState = next_state
  s_PrevStateAction = prev_state
  
  return blocking_state, next_state, prev_state
end

local function DrawPolicy(bmp, Q, start, goal, next_state, stochastic)
  local s = start
  local visited = {}
  while s ~= goal and not s_BlockingState[s] and not visited[s] do
    visited[s] = true
    local actions = GetMaxActions(Q[s])
    if not stochastic and #actions > 1 then break end
    local a = actions[1]
    s = next_state[s][a]
    local x, y, angle = StateToPosAngleReal(s)
    DrawRod(bmp, x, y, angle, {128, 128, 128}, {0, 0, 128})
  end
end

local function DrawPath(bmp, path)
  for _, s in ipairs(path) do
    local x, y, angle = StateToPosAngleReal(s)
    DrawRod(bmp, x, y, angle, {128, 128, 128}, {0, 0, 128})
  end
end

local function DrawPathFrames(bmp, path, episode, total_time, time)
  for idx, s in ipairs(path) do
    local img = bmp:Clone()
    local x, y, angle = StateToPosAngleReal(s)
    DrawRod(img, x, y, angle, {128, 128, 128}, {0, 0, 128})
    img:DrawText(0, 3, string.format("Step: %02d/%d", idx, #path), {128, 64, 255})
    img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Path_ep%d_t%d_%d_%d.bmp", episode, total_time, time, idx))
  end
end

local function FormatNumber(n)
  if n < 1000 then
    return tostring(n)
  else
    return tostring(n // 1000) .. "K"
  end
end

local function PrioritizedSweeping(start, goal, n, alpha, gamma, epsilon, treshold, bmp)
  local Q, Model = {}, { observed_states = { marked = {} }, observed_state_actions = {} }
  for s = 1, STATES do
    Q[s], Model[s] = {}, {}
    for _, a in ipairs(ACTIONS) do
      Q[s][a] = 0.0
    end
  end
  local PQueue = RBTree:new{ treshold = treshold }
  
  local R, R_goal = 0.0, 1.0
  local episode, total_time = 0, 0
  local shortest, shortest_path
  local last_lens, last_sum, last_num, last_idx, suboptimal_percents = {}, 0, 1000, 1, 98.5
  for i = 1, last_num do
    last_lens[i] = 1000000
    last_sum = last_sum + last_lens[i]
  end
  
  local start_time = os.clock()
  local frame_episodes = 10
  while (not s_MaxClockTime) or (os.clock() - start_time < s_MaxClockTime) do
    episode = episode + 1
    local time = 0
    local s = start
    local path = {}
    local cur_epsilon = epsilon / (1 + episode // 1000)
    while s ~= goal and not s_BlockingState[s] do
      local a = TakeEpsilonGreedyAction(s, Q, cur_epsilon, exp_rnd)
      local next_s = s_NextState[s][a]
      table.insert(path, next_s)
      local r = (next_s == goal) and R_goal or R
            
      -- register <s, a> in the Model and insert in priority queue if significant
      RegisterStateAction(Model, s, a, r, next_s)
      CheckPriority(PQueue, Q, s, a, r, next_s, gamma)
      
      -- simulation updates
      local sim_updates_left = n
      while sim_updates_left > 0 and not PQueue:IsEmpty() do
        -- update most significant <s, a>
        local max = PQueue:ExtractMax()        
        local s, a = max.s, max.a
        local record = Model[s][a]
        local r, next_s = record.r, record.next_s
        local max_Qa = table.max(Q[next_s])
        local update = alpha * (r + gamma * max_Qa - Q[s][a])
        Q[s][a] = Q[s][a] + update
        
        -- check all <prev_s, prev_a> predicted to lead to s
        local prev_sa = s_PrevStateAction[s]
        for prev_s, prev_a in ipairs(prev_sa) do
          local record = Model[prev_s] and Model[prev_s][prev_a]
          if record then
            CheckPriority(PQueue, Q, prev_s, prev_a, record.r, s, gamma)
          end
        end
        sim_updates_left = sim_updates_left - 1
      end
      s = next_s
      time, total_time = time + 1, total_time + 1
    end
    
    if s == goal then
      last_sum = last_sum - last_lens[last_idx] + time
      last_lens[last_idx] = time
      last_idx = (last_idx < last_num) and (last_idx + 1) or 1
      
      local avg_last_len = last_sum / last_num
      if not shortest or time < shortest then
        shortest = time
        shortest_path = path
        print(string.format("Clock: %ss, Episode: %d, Total Time: %d, New Optimal: %d, Suboptimal: %.2f[%.2f%%/.2%f%%]", os.clock() - start_time, episode, total_time, time, avg_last_len, 100.0 * shortest / avg_last_len, suboptimal_percents))
      end
      if 100.0 * shortest / avg_last_len >= suboptimal_percents then
        print(string.format("Last %d paths were less than %.2f%% suboptimal", last_num, suboptimal_percents))
        break
      end
    end
    if WRITE_FRAMES and episode % frame_episodes == 0 then
      local avg_last_len = last_sum / last_num
      print(string.format("Clock: %ss, Episode: %d, Total time: %d, Time[Shortest]: %d[%d], Suboptimal: %.2f[%.2f%%/%.2f%%]", os.clock() - start_time, episode, total_time, time, shortest, avg_last_len, 100.0 * shortest / avg_last_len, suboptimal_percents))
      
      local img = bmp:Clone()
      DrawPolicy(img, Q, start, goal, s_NextState, "stochastic")
      img:DrawText(0, 3, string.format("Episodes: %09d", episode), {128, 64, 255})
      local steps = string.format("Time Steps: %s", FormatNumber(total_time))
      img:DrawText(IMAGE_SIZE - 1 - string.len(steps) * 9, IMAGE_SIZE - 1 - 10, steps, {128, 64, 255})
      --img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Policy_%06d episode%010d steps%010d len%d.bmp", episode / frame_episodes, episode, total_time, shortest))
      img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Policy_%06d.bmp", episode / frame_episodes))
      
    end
  end
  
  print(string.format("Finish Clock: %ss, Finished in %d steps, %d episodes, min len: %d, n=%d, alpha = %.2f, gamma = %.2f, epsilon = %.3f", os.clock() - start_time, total_time, episode, shortest, n, alpha, gamma, epsilon))
  
  return shortest, shortest_path, episode, total_time, Q, os.clock() - start_time
end

local function RunRodManeuvering()
  -- scale obstacles coordinates and start/goal positions
  s_Obstacles.Start.x = math.floor(s_Obstacles.Start.x * OBSTACLES_SCALE)
  s_Obstacles.Start.y = math.floor(s_Obstacles.Start.y * OBSTACLES_SCALE)
  s_Obstacles.Goal.x = math.floor(s_Obstacles.Goal.x * OBSTACLES_SCALE)
  s_Obstacles.Goal.y = math.floor(s_Obstacles.Goal.y * OBSTACLES_SCALE)
  
  -- add last 1st vertex of each obstacle after the last, e.g. V[n+1]=V$[1]
  for idx, obstacle in ipairs(s_Obstacles) do
    for _, vert in ipairs(obstacle) do
        vert.x = math.floor(vert.x * OBSTACLES_SCALE)
        vert.y = math.floor(vert.y * OBSTACLES_SCALE)
    end
    table.insert(obstacle, { x = obstacle[1].x, y = obstacle[1].y })
  end
  
  local bmp = Bitmap.new(IMAGE_SIZE, IMAGE_SIZE)
  bmp:Fill(0, 0, IMAGE_SIZE - 1, IMAGE_SIZE - 1, {255, 255, 255})
  for _, obstacle in ipairs(s_Obstacles) do
    local last = obstacle[#obstacle]
    for _, v in ipairs(obstacle) do
      bmp:DrawLine(last.x, last.y, v.x, v.y, { 128, 128, 128 })
      last = v
    end
    local pt1, pt2, pt3 = obstacle[1], obstacle[2], obstacle[3]
    local dir_x = (pt1.x + pt3.x) / 2 - pt2.x
    local dir_y = (pt1.y + pt3.y) / 2 - pt2.y
    local len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    bmp:FloodFill(math.floor(pt2.x + 3 * dir_x / len), math.floor(pt2.y + 3 * dir_y / len), { 128, 128, 128 })
  end
  local start, goal = s_Obstacles.Start, s_Obstacles.Goal
  for k = 0, IMAGE_SIZE - 1, MOVE_DIST do
    bmp:DrawLine(k, 0, k, IMAGE_SIZE - 1, {128, 128, 128})
    bmp:DrawLine(0, k, IMAGE_SIZE - 1, k, {128, 128, 128})
  end
  
  local start_s = PosAngleRealToState(start.x, start.y, start.angle)
  local goal_s = PosAngleRealToState(goal.x, goal.y, goal.angle)
  local x, y, angle = StateToPosAngleReal(start_s)
  DrawRod(bmp, x, y, angle, { 255, 0, 0 }, { 0, 0, 255 })
  local x, y, angle = StateToPosAngleReal(goal_s)
  DrawRod(bmp, x, y, angle, { 0, 255, 0 }, { 0, 0, 255 })
  
  bmp:WriteBMP("RodManeuvering.bmp")
  
  InitStateTransitions()

  local n = { 1, 2, 3, 4, 5 }
  local alpha = { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 }
  local gamma = { 0.90, 0.91, 0.92, 0.93, 0.94, 0.95, 0.96, 0.97, 0.98, 0.99 }
  local epsilon = { 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10 }
  s_MaxClockTime = 300.0      -- 5 minutes
  
  local n = { 64 }
  local alpha = { 0.3 }
  local gamma = { 0.98 }
  local epsilon = { 0.1 }
  s_MaxClockTime = 72000.0      -- 20 hours
  
  local treshold = 0.0001
  
  local results = {}
  local best, _n, _alpha, _gamma, _epsilon
  for _, n in ipairs(n) do
    results[n] = {}
    for _, alpha in ipairs(alpha) do
      results[n][alpha] = {}
      for _, gamma in ipairs(gamma) do
        results[n][alpha][gamma] = {}
        for _, epsilon in ipairs(epsilon) do
          print(string.format("********* n=%d, alpha = %.2f, gamma = %.2f, epsilon = %.3f **********", n, alpha, gamma, epsilon))
          math.randomseed(1234)
          local len, path, episodes, steps, Q, time = PrioritizedSweeping(start_s, goal_s, n, alpha, gamma, epsilon, treshold, bmp)
          results[n][alpha][gamma][epsilon] = { len = len, path = path, episodes = episodes, steps = steps, Q = Q, time = time }
          if (not best) or (best.len > len) then
            best = results[n][alpha][gamma][epsilon]
            _n, _alpha, _gamma, _epsilon = n, alpha, gamma, epsilon
          end
          print(string.format("Best in %ss: len = %d, n=%d, alpha = %.2f, gamma = %.2f, epsilon = %.3f", best.time, best.len, _n, _alpha, _gamma, _epsilon))
        end
      end
    end
  end

  local img = bmp:Clone()
  DrawPolicy(img, best.Q, start_s, goal_s, s_NextState, "stochastic")
  img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Policy_ep%d_t%d_%d.bmp", best.episodes, best.steps, best.len))
  local img = bmp:Clone()
  DrawPath(img, best.path)
  img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Episode_ep%d_t%d_%d.bmp", best.episodes, best.steps, best.len))
  local img = bmp:Clone()
  DrawPathFrames(img, best.path, best.episodes, best.steps, best.len)

end

RunRodManeuvering()