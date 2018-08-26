local EPSILON = 0.0001

function SetLen(dir_x, dir_y, len, int)
  local cur_len = math.sqrt(dir_x * dir_x + dir_y * dir_y)
  dir_x = len * dir_x / cur_len
  dir_y = len * dir_y / cur_len
  
  if int then
    return math.floor(dir_x), math.floor(dir_y)
  else
    return dir_x, dir_y
  end
end

function PtInBounds2D(x, y, x1, y1, x2, y2)
	if x1 > x2 then
		x1, x2 = x2, x1
	end
	if y1 > y2 then
		y1, y2 = y2, y1
	end

	return x >= x1 - EPSILON and x <= x2 + EPSILON and y >= y1 - EPSILON and y <= y2 + EPSILON
end

function CalcLineEqParams2D(x1, y1, x2, y2)
		local a = y2 - y1
		local b = x1 - x2
		local c = x2 * y1 - x1 * y2
    
    return a, b, c
end

function LineInterLine2D(x1, y1, x2, y2, x3, y3, x4, y4)
	local a1, b1, c1 = CalcLineEqParams2D(x1, y1, x2, y2)
  local a2, b2, c2 = CalcLineEqParams2D(x3, y3, x4, y4)

	local D = a1 * b2 - a2 * b1
	if math.abs(D) < EPSILON then
		return
	end

	local x = (b1 * c2 - b2 * c1) / D
	local y = (a2 * c1 - a1 * c2) / D

	return x, y
end

function SegInterSeg2D(x1, y1, x2, y2, x3, y3, x4, y4)
  local x, y = LineInterLine2D(x1, y1, x2, y2, x3, y3, x4, y4)
  if x and y then
		if PtInBounds2D(x, y, x1, y1, x2, y2) and PtInBounds2D(x, y, x3, y3, x4, y4) then
      return x, y
    end
	end
end

function RotatePoint(x, y, angle, int)
  local sin = math.sin(angle)
  local cos = math.cos(angle)
  
	local rx = x * cos - y * sin
	local ry = x * sin + y * cos
  
  if int then
    return math.floor(rx), math.floor(ry)
  else
    return rx, ry
  end
end

function CalcOrientation(x1, y1, x2, y2)
  x2 = x2 or 0
  y2 = y2 or 0
  
	local x = x2 - x1
	local y = y2 - y1
  
	local ret = math.atan(y / x)
	ret = (ret < 0) and (ret + math.pi) or ret
	
  return ret
end

function CalcSignedAngleBetween(x1, y1, x2, y2)
	local a1 = math.atan(y1 / x1)
	local a2 = math.atan(y2 / x2)

	local res1 = a2 - a1
	local res2 = (a1 > a2) and (a2 - a1 + math.pi) or (a2 - a1 - math.pi)

	local ares1 = math.abs(res1)
	local ares2 = math.abs(res2)

	return (ares1 == ares2) and Max(res1, res2) or ((ares1 < ares2) and res1 or res2)
end

function TriangleArea2D(x1, y1, x2, y2, x3, y3)
	return math.abs((x1 * y2 - x2 * y1) + (x2 * y3 - x3 * y2) + (x3 * y1 - x1 * y3)) / 2.0
end

function PointInsideTriangle(x, y, x1, y1, x2, y2, x3, y3)
	local area = TriangleArea2D(x1, y1, x2, y2, x3, y3)
	local q1 = TriangleArea2D(x, y, x1, y1, x2, y2)
	local q2 = TriangleArea2D(x, y, x2, y2, x3, y3)
	local q3 = TriangleArea2D(x, y, x3, y3, x1, y1)

	return math.abs(q1 + q2 + q3 - area) < EPSILON
end

-- NOTE: assumes poly[n + 1] == poly[1]
function PolyArea2D(poly)
  local n = #poly - 1
  if #poly < 3 then return 0 end
  
  local area = 0
  local i, j, k = 2, 3, 1
  while i <= n do
    area = area + poly[i].x * (poly[j].y - poly[k].y)
    i, j, k = i + 1, j + 1, k + 1
  end
  area = area + poly[n + 1].x * (poly[2].y - poly[n].y)
  
  return area / 2.0
end

-- NOTE: assumes poly[n + 1] == poly[1]
function PtInConvexPoly2D(x, y, poly)
  local area = PolyArea2D(poly)
  local tri_area = 0
  for i = 1, #poly - 1 do
    tri_area = tri_area + TriangleArea2D(x, y, poly[i].x, poly[i].y, poly[i + 1].x, poly[i + 1].y)
  end
  
  return math.abs(area - tri_area) < EPSILON
end