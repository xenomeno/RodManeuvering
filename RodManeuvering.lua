dofile("Bitmap.lua")
dofile("Geometry.lua")
dofile("Graphics.lua")

local RBTree = dofile("RBTree.lua")

local IMAGE_SIZE      = 1080
local OBSTACLES_SCALE = 2.7       -- scale 1.0 corresponds to IMAGE_SIZE = 400

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

function Min(a, b) return (a < b) and a or b end
function Max(a, b) return (a > b) and a or b end

function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	else
		return x
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

function string.format_table(fmt_str, params_tbl, num_fmt)
  local function repl_func(param)
    local value = params_tbl[param]
    if value ~= nil then
      if type(value) == "bool" then
        return tostring(value)
      elseif type(value) == "number" then
        local value_fmt = num_fmt and num_fmt[param]
        return value_fmt and string.format(value_fmt, value) or tostring(value)
      else
        return tostring(value)
      end
    else
      return string.format("<%s - invalid param!>", param)
    end
  end

  local str = string.gsub(fmt_str, "<([%w_]+)>", repl_func)
  
  return str
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
    Model.prev[next_s][a] = s
    return
  end
  
  Model[s][a] = { r = r, next_s = next_s }  
  Model.prev[next_s][a] = s
end

local function GetMaxActions(Qs)
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
      local present = PQueue.pair[s] and PQueue.pair[s][a]
      if present then
        if present < priority then
          -- if pair is present in the queue only the higher priority is left
          PQueue:delete(present, function(node) return node.s == s and node.a == a end)
          PQueue:insert({key = priority, s = s, a = a})
          PQueue.pair[s][a] = priority
        end
      else
        -- new pair
        PQueue:insert({key = priority, s = s, a = a})
        PQueue.pair[s] = PQueue.pair[s] or {}
        PQueue.pair[s][a] = priority
      end
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
local s_NextState = false

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
  
  time = os.clock() - time
  print(string.format("Blocking states & transition precalculation time: %ss", time))
  
  s_BlockingState = blocking_state
  s_NextState = next_state
  
  return blocking_state, next_state
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

local function PrioritizedSweeping(start, goal, n, alpha, gamma, epsilon, treshold, max_clock_time, bmp, frames)
  local Q, Model = {}, { prev = {} }
  for s = 1, STATES do
    Q[s], Model[s], Model.prev[s] = {}, {}, {}
    for _, a in ipairs(ACTIONS) do
      Q[s][a] = 0.0
    end
  end
  local PQueue = RBTree:new{ treshold = treshold, pair = {} }
  
  local R, R_goal = 0.0, 1.0
  local episode, total_time, total_updates = 0, 0, 0
  local shortest, shortest_path
  local last_lens, last_sum, last_num, last_idx, suboptimal_percents = {}, 0, 1000, 1, 98.5
  for i = 1, last_num do
    last_lens[i] = 1000000
    last_sum = last_sum + last_lens[i]
  end
  local zero_updates_episodes, max_zero_updates_episodes = 0, 10
  
  local start_time = os.clock()
  local ep_stats = {["On-Line"] = {}, ["Off-Line"] = {}, ["Updates"] = {}, ["PQueue"] = {} }
  while (not max_clock_time) or (os.clock() - start_time < max_clock_time) do
    episode = episode + 1
    local time = 0
    local s = start
    local path = {}
    local cur_epsilon = epsilon / (1 + episode // 1000)
    local last_updates = total_updates
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
        PQueue.pair[s][a] = nil
        local record = Model[s][a]
        local r, next_s = record.r, record.next_s
        local max_Qa = table.max(Q[next_s])
        local update = alpha * (r + gamma * max_Qa - Q[s][a])
        Q[s][a] = Q[s][a] + update
        total_updates = total_updates + 1
        
        -- check all <prev_s, prev_a> predicted to lead to s
        local prev_sa = Model.prev[s]
        for prev_a, prev_s in pairs(prev_sa) do
          CheckPriority(PQueue, Q, prev_s, prev_a, Model[prev_s][prev_a].r, s, gamma)
        end
        sim_updates_left = sim_updates_left - 1
      end
      s = next_s
      time, total_time = time + 1, total_time + 1
      ep_stats["Updates"][total_time] = total_updates
      ep_stats["PQueue"][total_time] = PQueue:ElementsCount()
    end
    zero_updates_episodes = (last_updates == total_updates) and (zero_updates_episodes + 1) or 0
    if zero_updates_episodes >= max_zero_updates_episodes then
      print(string.format("Last %d episodes were with 0 updates", max_zero_updates_episodes))
      break
    end
    
    if s == goal then
      last_sum = last_sum - last_lens[last_idx] + time
      last_lens[last_idx] = time
      last_idx = (last_idx < last_num) and (last_idx + 1) or 1
      
      local avg_last_len = last_sum / last_num
      if not shortest or time < shortest then
        shortest, shortest_path = time, path
        PQueue.treshold = treshold
        print(string.format("Clock: %ss, Episode: %d, Total Time[Updates]: %d[%d], New Optimal: %d, Suboptimal: %.2f[%.2f%%/%.2f%%], PQueue[Max]: %d[%d]", os.clock() - start_time, episode, total_time, total_updates, time, avg_last_len, 100.0 * shortest / avg_last_len, suboptimal_percents, PQueue:ElementsCount(), PQueue:MaxElementsCount()))
      end
      table.insert(ep_stats["On-Line"], { x = episode, y = time })
      table.insert(ep_stats["Off-Line"], { x = episode, y = shortest })
      if 100.0 * shortest / avg_last_len >= suboptimal_percents then
        print(string.format("Last %d paths were more than %.2f%% suboptimal", last_num, suboptimal_percents))
        break
      end
    end
    if frames and episode % frames == 0 then
      local avg_last_len = last_sum / last_num
      print(string.format("Clock: %ss, Episode: %d, Total time[updates]: %d[%d], Time[Shortest]: %d[%d], Suboptimal: %.2f[%.2f%%/%.2f%%], PQueue[Max]: %d[%d]", os.clock() - start_time, episode, total_time, total_updates, time, shortest, avg_last_len, 100.0 * shortest / avg_last_len, suboptimal_percents, PQueue:ElementsCount(), PQueue:MaxElementsCount()))
      local img = bmp:Clone()
      DrawPolicy(img, Q, start, goal, s_NextState, "stochastic")
      img:DrawText(0, 3, string.format("Episodes: %09d", episode), {128, 64, 255})
      local steps = string.format("Time Steps: %s", FormatNumber(total_time))
      img:DrawText(IMAGE_SIZE - 1 - string.len(steps) * 9, IMAGE_SIZE - 1 - 10, steps, {128, 64, 255})
      img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Policy_%06d.bmp", episode / frames))
    end
  end
  
  print(string.format("Finish Clock: %ss, Finished in %d[%d] steps[updates], %d episodes, min len: %d, n=%d, alpha = %.2f, gamma = %.2f, epsilon = %.3f, Max PQueue size: %d", os.clock() - start_time, total_time, total_updates, episode, shortest, n, alpha, gamma, epsilon, PQueue:MaxElementsCount()))
  
  if frames then
    local img = bmp:Clone()
    DrawPolicy(img, Q, start_s, goal_s, s_NextState, "stochastic")
    img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Policy_ep%d_t%d_%d.bmp", episode, total_time, shortest))
    local img = bmp:Clone()
    DrawPath(img, shortest_path)
    img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_Episode_ep%d_t%d_%d.bmp", episode, total_time, shortest))
    local img = bmp:Clone()
    DrawPathFrames(img, shortest_path, episode, total_time, shortest)
  end
  
  return
  {
    path = shortest_path,
    episodes = episode,
    time_steps = total_time,
    updates = total_updates,
    real_time = os.clock() - start_time,
    ep_stats = ep_stats
  }
end

local function FindShortestPathBFS(start, goal, bmp)
  local marked = { [start] = true }
  local action = {}
  local steps = 0
  local wave = {start}
  while #wave > 0 do
    steps = steps + 1
    local new_wave = {}
    for _, s in ipairs(wave) do
      if s == goal then
        steps = steps - 1
        new_wave = {}
        break
      end
      for _, a in ipairs(ACTIONS) do
        local next_s = s_NextState[s][a]
        if not marked[next_s] and not s_BlockingState[next_s] then
          marked[next_s] = true
          table.insert(new_wave, next_s)
          action[next_s] = { s = s, a = a }
        end
      end
    end
    wave = new_wave
  end
  
  local path = {}
  while true do
    local x, y, angle = StateToPosAngleReal(goal)
    if bmp then
      local img = bmp:Clone()
      DrawRod(img, x, y, angle, {128, 128, 128}, {0, 0, 128})
      img:WriteBMP(string.format("RodManeuveringImages/RodManeuvering_BFS_%d.bmp", steps - #path))
    end
    if goal == start then break end
    table.insert(path, 1, goal)
    goal = action[goal].s
  end
  
  return path
end

function table.clamp(tbl, min, max)
  if type(tbl[1]) == "number" then
    for idx, y in ipairs(tbl) do
      tbl[idx] = clamp(y, min, max)
    end
  else
    for _, entry in ipairs(tbl) do
      entry.y = clamp(entry.y, min, max)
    end
  end
end

function table.averagized(tbl, avg_span)
  local k, len = 1, #tbl
  if type(tbl[1]) == "number" then
    while k <= len do
      local sum_x, sum_y, count = 0, 0, Min(avg_span, len - k + 1)
      for i = k, k + count - 1 do
        sum_x = sum_x + i
        sum_y = sum_y + tbl[i]
      end
      tbl[k // avg_span] = { x = k // avg_span, y = sum_y / count }
      k = k + count
    end
  else
    while k <= len do
      local sum_x, sum_y, count = 0, 0, Min(avg_span, len - k + 1)
      for i = k, k + count - 1 do
        sum_x = sum_x + tbl[i].x
        sum_y = sum_y + tbl[i].y
      end
      tbl[k // avg_span] = { x = k // avg_span, y = sum_y / count }
      k = k + count
    end
  end
  len = len // avg_span
  while #tbl > len do table.remove(tbl) end
  
  return tbl
end

local function DrawGraphics(filename, graphs, label, int_x, skip_KP, div)
  local bmp = Bitmap.new(IMAGE_SIZE, IMAGE_SIZE, {0, 0, 0})
  DrawGraphs(bmp, graphs, div, nil, int_x, "int", skip_KP)
  local text_w = bmp:MeasureText(label)
  bmp:DrawText((IMAGE_SIZE - text_w) // 2, 5, label, {128, 128, 128})
  bmp:WriteBMP(filename)
end

local function InitRodManeuvering()
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
  InitStateTransitions()
end

local function RunRodManeuvering(test)
  local bmp = Bitmap.new(IMAGE_SIZE, IMAGE_SIZE, {255, 255, 255})
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
  
  local shortest = FindShortestPathBFS(start_s, goal_s)
  print(string.format("BFS length: %d", #shortest))

  local treshold = 0.0001
  
  local online = { funcs = {}, name_y = "Length" }
  local offline = { funcs = {}, name_y = "Length" }
  local updates = { funcs = {}, name_y = "Updates" }
  local pqueue = { funcs = {}, name_y = "PQueue Size" }
  local color = {{255,0,0},{0,255,0},{0,0,255},{255,255,0},{255,0,255},{0,255,255},{255,255,255},{128,128,128},{64,128,255}}
  
  local best
  local max_axis_episodes, max_axis_time_steps = 0, 0
  local stats = {}
  if test.to_plot and test.plot_vs then
    for graph_name, descr in pairs(test.to_plot) do
      stats[graph_name] = { funcs = {}, name_x = test.name_x, name_y = descr.name_y }
      stats[graph_name].funcs[descr.func_name] = {color = descr.color}
    end
  end
  for idx_n, n in ipairs(test.n) do
    for idx_alpha, alpha in ipairs(test.alpha) do
      for idx_gamma, gamma in ipairs(test.gamma) do
        for idx_epsilon, epsilon in ipairs(test.epsilon) do
          local indices = { ["n"] = idx_n, ["alpha"] = idx_alpha, ["gamma"] = idx_gamma, ["epsilon"] = idx_epsilon }
          local values = { ["n"] = n, ["alpha"] = alpha, ["gamma"] = gamma, ["epsilon"] = epsilon }
          local names = { ["n"] = "n", ["alpha"] = "A", ["gamma"] = "G", ["epsilon"] = "Eps" }
          local idx, vs, param = indices[test.plot_vs], values[test.plot_vs], names[test.plot_vs]
          local name = test.plot_vs and string.format_table("<name>=<value>", { name = param, value = vs }, test.num_fmt) or ""
          print(string.format("********* %s: n=%d, alpha = %.2f, gamma = %.2f, epsilon = %.3f **********", name, n, alpha, gamma, epsilon))
          math.randomseed(1234)
          local result = PrioritizedSweeping(start_s, goal_s, n, alpha, gamma, epsilon, treshold, test.max_time, bmp, test.frames)
          if (not best) or (#best.path > #result.path) then
            best = result
            best.n, best.alpha, best.gamma, best.epsilon = n, alpha, gamma, epsilon
          end
          print(string.format("Best in %ss: len = %d, n=%d, alpha = %.2f, gamma = %.2f, epsilon = %.3f", best.time_steps, #best.path, best.n, best.alpha, best.gamma, best.epsilon))
          
          local avg_span = math.pow(10, 2 + (math.ceil(math.log10(result.episodes)) // 10))
          table.clamp(result.ep_stats["On-Line"], 0, 2 * #result.path)
          online.funcs[name] = table.averagized(result.ep_stats["On-Line"], avg_span)
          online.funcs[name].color = color[idx]
          online.name_x = string.format("Episode x %d", avg_span)
          table.clamp(result.ep_stats["Off-Line"], 0, 2 * #result.path)
          offline.funcs[name] = table.averagized(result.ep_stats["Off-Line"], avg_span)
          offline.funcs[name].color = color[idx]
          offline.name_x = string.format("Episode x %d", avg_span)
          max_axis_episodes = Max(max_axis_episodes, #online.funcs[name])
                    
          local avg_span = math.pow(10, 2 + (math.ceil(math.log10(result.episodes)) // 10))
          updates.funcs[name] = table.averagized(result.ep_stats["Updates"], avg_span)
          updates.funcs[name].color = color[idx]
          updates.name_x = string.format("Time Step x %d", avg_span)
          pqueue.funcs[name] = table.averagized(result.ep_stats["PQueue"], avg_span)
          pqueue.funcs[name].color = color[idx]
          pqueue.name_x = string.format("Time Step x %d", avg_span)
          max_axis_time_steps = Max(max_axis_time_steps, #updates.funcs[name])

          if test.to_plot then
            for graph_name, descr in pairs(test.to_plot) do
              table.insert(stats[graph_name].funcs[descr.func_name], {x = vs, y = result[graph_name], text = tostring(#result.path)})
              descr.params = descr.params or {n = n, alpha = alpha, gamma = gamma, epsilon = epsilon}
            end
          end
        end
      end
    end
  end
  
  if test.to_plot and test.plot_vs then
    for graph_name, descr in pairs(test.to_plot) do
      DrawGraphics(descr.filename, stats[graph_name], string.format_table(test.title, descr.params, test.num_fmt), nil, nil, test.plot_div)
    end
  end

  if test.online then
    online.funcs["shortest"] = { {x = 0, y = #shortest}, {x = max_axis_episodes, y = #shortest}, color = {128, 128, 128} }
    DrawGraphics(test.online, online, string.format("On-line Performance: %d, BFS Shortest: %d", #best.path, #shortest), "int x", "skip KP")
  end
  if test.offline then
    offline.funcs["shortest"] = { {x = 0, y = #shortest}, {x = max_axis_episodes, y = #shortest}, color = {128, 128, 128} }
    DrawGraphics(test.offline, offline, string.format("Off-line Performance: %d, BFS Shortest: %d", #best.path, #shortest), "int x", "skip KP")
  end
  if test.updates then
    DrawGraphics(test.updates, updates, string.format("Updates vs Time Step"), "int x", "skip KP")
  end
  if test.pqueue then
    DrawGraphics(test.pqueue, pqueue, string.format("Priority Queue Size vs Time Step"), "int x", "skip KP")
  end
end

local s_Tests =
{
  ["SimUpdates"] =
  {
    title = "alpha=<alpha>, gamma=<gamma>, epsilon=<epsilon>",
    num_fmt = { ["alpha"] = "%.2f", ["gamma"] = "%.2f", ["epsilon"] = "%.2f" },
    n = { 1, 2, 4, 8, 16, 32, 64, 128, 256 },
    alpha = { 0.1 }, gamma = { 0.97 }, epsilon = { 0.1 },
    online = "RodManeuveringImages/RodManeuvering_SimUpdates_Online.bmp",
    offline = "RodManeuveringImages/RodManeuvering_SimUpdates_Offline.bmp",
    name_x = "Simulation Updates",
    to_plot =
    {
      ["time_steps"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_TimeSteps.bmp",
        func_name = "n vs Time Steps", name_y = "Time Steps", color = {0, 255, 0},
      },
      ["updates"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_Updates.bmp",
        func_name = "n vs Total Updates", name_y = "Total updates", color = {0, 255, 0},
      },
      ["episodes"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_Episodes.bmp",
        func_name = "n vs Episodes", name_y = "Episodes", color = {0, 255, 0},
      },
      ["real_time"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_RealTime.bmp",
        func_name = "n vs Real Time", name_y = "Real Time(s)", color = {0, 255, 0},
      },
    },
    plot_vs = "n",
  }
}

local s_Tests =
{
  ["SimUpdates"] =
  {
    title = "alpha=<alpha>, gamma=<gamma>, epsilon=<epsilon>",
    num_fmt = { ["alpha"] = "%.2f", ["gamma"] = "%.2f", ["epsilon"] = "%.2f" },
    n = { 1, 2, 4, 8, 16, 32, 64, 128, 256 },
    alpha = { 0.1 }, gamma = { 0.97 }, epsilon = { 0.1 },
    online = "RodManeuveringImages/RodManeuvering_SimUpdates_Online.bmp",
    offline = "RodManeuveringImages/RodManeuvering_SimUpdates_Offline.bmp",
    updates = "RodManeuveringImages/RodManeuvering_SimUpdates_Updates.bmp",
    pqueue = "RodManeuveringImages/RodManeuvering_SimUpdates_PQueueSize.bmp",
    name_x = "Simulation Updates",
    max_time = 300,
    to_plot =
    {
      ["time_steps"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_TimeSteps.bmp",
        func_name = "n vs Time Steps", name_y = "Time Steps", color = {0, 255, 0},
      },
      ["updates"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_Updates.bmp",
        func_name = "n vs Total Updates", name_y = "Total updates", color = {0, 255, 0},
      },
      ["episodes"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_Episodes.bmp",
        func_name = "n vs Episodes", name_y = "Episodes", color = {0, 255, 0},
      },
      ["real_time"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_SimUpdates_vs_RealTime.bmp",
        func_name = "n vs Real Time", name_y = "Real Time(s)", color = {0, 255, 0},
      },
    },
    plot_vs = "n",
  },
  ["Alpha"] =
  {
    title = "n=<n>, gamma=<gamma>, epsilon=<epsilon>",
    num_fmt = { ["n"] = "%d", ["gamma"] = "%.2f", ["epsilon"] = "%.2f" },
    alpha = { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9 },
    n = { 32 }, gamma = { 0.97 }, epsilon = { 0.1 },
    online = "RodManeuveringImages/RodManeuvering_Alpha_Online.bmp",
    offline = "RodManeuveringImages/RodManeuvering_Alpha_Offline.bmp",
    updates = "RodManeuveringImages/RodManeuvering_Alpha_Updates.bmp",
    pqueue = "RodManeuveringImages/RodManeuvering_Alpha_PQueueSize.bmp",
    name_x = "Alpha",
    max_time = 300,
    to_plot =
    {
      ["time_steps"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Alpha_vs_TimeSteps.bmp",
        func_name = "Alpha vs Time Steps", name_y = "Time Steps", color = {0, 255, 0},
      },
      ["updates"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Alpha_vs_Updates.bmp",
        func_name = "Alpha vs Total Updates", name_y = "Total updates", color = {0, 255, 0},
      },
      ["episodes"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Alpha_vs_Episodes.bmp",
        func_name = "Alpha vs Episodes", name_y = "Episodes", color = {0, 255, 0},
      },
      ["real_time"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Alpha_vs_RealTime.bmp",
        func_name = "Alpha vs Real Time", name_y = "Real Time(s)", color = {0, 255, 0},
      },
    },
    plot_vs = "alpha",
  },
  ["Gamma"] =
  {
    title = "n=<n>, alpha=<alpha>, epsilon=<epsilon>",
    num_fmt = { ["n"] = "%d", ["alpha"] = "%.2f", ["epsilon"] = "%.2f" },
    gamma = { 0.92, 0.93, 0.94, 0.95, 0.96, 0.97, 0.98, 0.99 },
    n = { 32 }, alpha = { 0.1 }, epsilon = { 0.1 },
    online = "RodManeuveringImages/RodManeuvering_Gamma_Online.bmp",
    offline = "RodManeuveringImages/RodManeuvering_Gamma_Offline.bmp",
    updates = "RodManeuveringImages/RodManeuvering_Gamma_Updates.bmp",
    pqueue = "RodManeuveringImages/RodManeuvering_Gamma_PQueueSize.bmp",
    name_x = "Gamma",
    max_time = 300,
    to_plot =
    {
      ["time_steps"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Gamma_vs_TimeSteps.bmp",
        func_name = "Gamma vs Time Steps", name_y = "Time Steps", color = {0, 255, 0},
      },
      ["updates"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Gamma_vs_Updates.bmp",
        func_name = "Gamma vs Total Updates", name_y = "Total updates", color = {0, 255, 0},
      },
      ["episodes"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Gamma_vs_Episodes.bmp",
        func_name = "Gamma vs Episodes", name_y = "Episodes", color = {0, 255, 0},
      },
      ["real_time"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Gamma_vs_RealTime.bmp",
        func_name = "Gamma vs Real Time", name_y = "Real Time(s)", color = {0, 255, 0},
      },
    },
    plot_vs = "gamma",
    plot_div = 4,
  },
  ["Epsilon"] =
  {
    title = "n=<n>, alpha=<alpha>, gamma=<gamma>",
    num_fmt = { ["n"] = "%d", ["alpha"] = "%.2f",["gamma"] = "%.2f" },
    epsilon = { 0.1, 0.05, 0.01, 0.005, 0.001 },
    n = { 32 }, alpha = { 0.1 }, gamma = { 0.97 },
    online = "RodManeuveringImages/RodManeuvering_Epsilon_Online.bmp",
    offline = "RodManeuveringImages/RodManeuvering_Epsilon_Offline.bmp",
    updates = "RodManeuveringImages/RodManeuvering_Epsilon_Updates.bmp",
    pqueue = "RodManeuveringImages/RodManeuvering_Epsilon_PQueueSize.bmp",
    name_x = "Gamma",
    max_time = 300,
    to_plot =
    {
      ["time_steps"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Epsilon_vs_TimeSteps.bmp",
        func_name = "Epsilon vs Time Steps", name_y = "Time Steps", color = {0, 255, 0},
      },
      ["updates"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Epsilon_vs_Updates.bmp",
        func_name = "Epsilon vs Total Updates", name_y = "Total updates", color = {0, 255, 0},
      },
      ["episodes"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Epsilon_vs_Episodes.bmp",
        func_name = "Epsilon vs Episodes", name_y = "Episodes", color = {0, 255, 0},
      },
      ["real_time"] =
      {
        filename = "RodManeuveringImages/RodManeuvering_Epsilon_vs_RealTime.bmp",
        func_name = "Epsilon vs Real Time", name_y = "Real Time(s)", color = {0, 255, 0},
      },
    },
    plot_vs = "epsilon",
    plot_div = 4,
  },
  ["PolicyPath"] =
  {
    title = "n=<n>, alpha=<alpha>, gamma=<gamma>, epsilon=<epsilon>",
    num_fmt = { ["n"] = "%d", ["alpha"] = "%.2f", ["epsilon"] = "%.3f", ["gamma"] = "%.2f" },    
    n = { 32 }, alpha = { 0.1 }, gamma = { 0.98 }, epsilon = { 0.1 },
    online = "RodManeuveringImages/RodManeuvering_PolicyPath_Online.bmp",
    offline = "RodManeuveringImages/RodManeuvering_PolicyPath_Offline.bmp",
    updates = "RodManeuveringImages/RodManeuvering_PolicyPath_Updates.bmp",
    pqueue = "RodManeuveringImages/RodManeuvering_PolicyPath_PQueueSize.bmp",
    frames = 1,
  }
}

InitRodManeuvering()
RunRodManeuvering(s_Tests.Alpha)
--for _, test in pairs(s_Tests) do RunRodManeuvering(test) end  -- perform all tests