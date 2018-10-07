local DEFAULT_SCALE   = 1
local DEFAULT_SPACING = 1

Bitmap = {}
Bitmap.__index = Bitmap
 
function Bitmap.new(width, height, init_color)
    init_color = init_color or { 255, 255, 255 }
    
    local self = {}
    setmetatable(self, Bitmap)
    
    local data = {}
    for y = 0, height - 1 do
      data[y] = {}
      for x = 0, width - 1 do
        data[y][x] = init_color
      end
    end
    self.width = width
    self.height = height
    self.data = data
    
    return self
end
 
function Bitmap:WriteRawChar(file, c)
    file:write(string.tochar(c))
end

function Bitmap:WriteRawInt(file, int)
    file:write(string.char(int & 0x000000FF))
    file:write(string.char((int & 0x0000FF00) >> 8))
    file:write(string.char((int & 0x00FF0000) >> 16))
    file:write(string.char((int & 0xFF000000) >> 24))
end
 
function Bitmap:WriteBMP(filename)
    local fh = io.open(filename, 'w')
    if not fh then
        io.flush()
        collectgarbage("collect")
        fh = io.open(filename, 'w')
    end
    if not fh then
        error(string.format("failed to open %q for writing", filename))
    else
        fh:setvbuf("full", 512 * 1024)
        
        local extra_bytes = 4 - (self.width * 3) % 4
        extra_bytes = (extra_bytes == 4) and 0 or extra_bytes
        local padded_size = (self.width * 3 + extra_bytes) * self.height
        
        -- headers - "BM" identifier in bytes 0 and 1 is NOT included in these "headers".
        local headers = {}
        headers[1] = padded_size + 54     -- bfSize: whole file size
        headers[2] = 0                    -- bfReserved
        headers[3] = 54                   -- bfOffbits
        headers[4] = 40                   -- biSize
        headers[5] = self.width           -- biWidth
        headers[6] = self.height          -- biHeight
        headers[7] = (24 << 16) + 1       -- biPlanes and biBitCount
        headers[8] = 0                    -- biCompression
        headers[9] = padded_size          -- biSizeImage
        headers[10] = 0                   -- biXPelsPerMeter
        headers[11] = 0                   -- biYPelsPerMeter
        headers[12] = 0                   -- biClrUsed
        headers[13] = 0                   -- biClrImportant
        
        -- headers write - when printing ints and shorts white them char per char to avoid endian issues
        fh:write("BM")
        for i = 1, 13 do
            self:WriteRawInt(fh, headers[i])
        end
      
        for y = self.height - 1, 0, -1 do
            local row = self.data[y]
            for x = 0, self.width - 1 do
                local pixel = row[x]
                fh:write(string.char(pixel[3]))
                fh:write(string.char(pixel[2]))
                fh:write(string.char(pixel[1]))
            end
        end
    end
    
    fh:flush()
end
 
function Bitmap:Fill(x, y, width, height, color)
    width = (width == nil) and self.width or width
    height = (height == nil) and self.height or height
    width = x + width - 1
    height = y + height - 1
    for i = y, height do
      local data = self.data[i]
        for j = x, width do
            data[j] = color
        end
    end
end
 
function Bitmap:SetPixel(x, y, color)
    if x >= self.width then
        --error("x is bigger than self.width!")
        return false
    elseif x < 0 then
        --error("x is smaller than 0!")
        return false
    elseif y >= self.height then
        --error("y is bigger than self.height!")
        return false
    elseif y < 0 then
        --error("y is smaller than 0!")
        return false
    end
    self.data[y][x] = color
    return true
end

function Bitmap:DrawLineLow(x0, y0, x1, y1, color)
  local dx = x1 - x0
  local dy = y1 - y0
  local yi = 1
  if dy < 0 then
    yi = -1
    dy = -dy
  end
  local D = 2*dy - dx
  local y = y0

  for x = x0, x1 do
    self:SetPixel(x, y, color)
    if D > 0 then
       y = y + yi
       D = D - 2 * dx
    end
    D = D + 2 * dy
  end
end

function Bitmap:DrawLineHigh(x0, y0, x1, y1, color)
  local dx = x1 - x0
  local dy = y1 - y0
  local xi = 1
  if dx < 0 then
    xi = -1
    dx = -dx
  end
  local D = 2*dx - dy
  local x = x0

  for y = y0, y1 do
    self:SetPixel(x, y, color)
    if D > 0 then
       x = x + xi
       D = D - 2 * dy
    end
    D = D + 2 * dx
  end
end

function Bitmap:DrawLine(x0, y0, x1, y1, color)
  if math.abs(y1 - y0) < math.abs(x1 - x0) then
    if x0 > x1 then
      self:DrawLineLow(x1, y1, x0, y0, color)
    else
      self:DrawLineLow(x0, y0, x1, y1, color)
    end
  else
    if y0 > y1 then
      self:DrawLineHigh(x1, y1, x0, y0, color)
    else
      self:DrawLineHigh(x0, y0, x1, y1, color)
    end
  end
end

function Bitmap:FloodFill(x, y, color)
  local data = self.data
  local src_clr = data[y][x]
  local wave = { { x = x, y = y }}
  while #wave > 0 do
    local x, y = wave[1].x, wave[1].y
    table.remove(wave, 1)
    data[y][x] = color
    if x > 0 and data[y][x - 1] == src_clr then
      table.insert(wave, { x = x - 1, y = y })
      data[y][x - 1] = color
    end
    if x + 1 < self.width and data[y][x + 1] == src_clr then
      table.insert(wave, { x = x + 1, y = y })
      data[y][x + 1] = color
    end
    if y > 0 and data[y - 1][x] == src_clr then
      table.insert(wave, { x = x, y = y - 1 })
      data[y - 1][x] = color
    end
    if y + 1 < self.height and data[y + 1][x] == src_clr then
      data[y + 1][x] = color
      table.insert(wave, { x = x, y = y + 1 })
    end
  end
end

function Bitmap:DrawBox(x1, y1, x2, y2, color)
  local data = self.data
  local row1 = data[y1]
  local row2 = data[y2]
  for x = x1, x2 do
    row1[x] = color
    row2[x] = color
  end
  for y = y1 + 1, y2 - 1 do
    data[y][x1] = color
    data[y][x2] = color
  end
end

function Bitmap:Clone()
  local bmp = Bitmap.new(self.width, self.height)
  local w, h, data = self.height, self.width, self.data
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      bmp.data[y][x] = data[y][x]
    end
  end
  
  return bmp
end

local s_Char =
{
  [0] =
  {
    "  ****  ",
    " *    * ",
    " *    * ",
    " *   ** ",
    " * ** * ",
    " **   * ",
    " *    * ",
    " *    * ",
    "  ****  ",
  },
  [1] =
  {
    "    *   ",
    "   **   ",
    "  * *   ",
    " *  *   ",
    "    *   ",
    "    *   ",
    "    *   ",
    "    *   ",
    "  ***** ",
  },
  [2] =
  {
    " ****** ",
    "*      *",
    "       *",
    "      * ",
    "     *  ",
    "    *   ",
    "   *    ",
    "  *     ",
    " *******",    
  },
  [3] =
  {
    "  ***   ",
    " *   ** ",
    "      * ",
    "     ** ",
    "   **   ",
    "     ** ",
    "      * ",
    " *   ** ",
    "  ***   ",
  },
  [4] =
  {
    " *   *  ",
    " *   *  ",
    " *   *  ",
    " *   *  ",
    " *****  ",
    "     *  ",
    "     *  ",
    "     *  ",
    "   **** ",
  },
  [5] =
  {
    " *****  ",
    " *      ",
    " *      ",
    " *      ",
    " ****   ",
    "     ** ",
    "      * ",
    " *   ** ",
    "  ***   ",
  },
  [6] =
  {
    "  ****  ",
    " *    * ",
    "*       ",
    "*       ",
    "* ****  ",
    "**    * ",
    "*      *",
    " *    * ",
    "  ****  ",
  },
  [7] =
  {
    " *******",
    "       *",
    "      * ",
    "     *  ",
    "    *   ",
    "    *   ",
    "    *   ",
    "    *   ",
    "   ***  ",
  },
  [8] =
  {
    "  ****  ",
    " *    * ",
    " *    * ",
    " *    * ",
    "  ****  ",
    " *    * ",
    " *    * ",
    " *    * ",
    "  ****  ",
  },
  [9] =
  {
    "  ****  ",
    " *    * ",
    " *    * ",
    " *    * ",
    "  ***** ",
    "      * ",
    "      * ",
    "     *  ",
    "  ***   ",
  },
  [" "] =
  {
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
  },
  ["."] =
  {
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "**      ",
    "**      ",
  },
  [","] =
  {
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "  **    ",
    "* **    ",
    " **     ",
  },
  ["-"] =
  {
    "        ",
    "        ",
    "        ",
    "        ",
    "********",
    "        ",
    "        ",
    "        ",
    "        ",
  },
  ["+"] =
  {
    "        ",
    "   **   ",
    "   **   ",
    "   **   ",
    "********",
    "   **   ",
    "   **   ",
    "   **   ",
    "        ",
  },
  ["_"] =
  {
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
    "********",
  },
  ["="] =
  {
    "        ",
    "        ",
    "        ",
    "********",
    "        ",
    "********",
    "        ",
    "        ",
    "        ",
  },
  ["!"] =
  {
    "   **   ",
    "   **   ",
    "   **   ",
    "   **   ",
    "   **   ",
    "   **   ",
    "   **   ",
    "        ",
    "   **   ",
  },
  ["%"] =
  {
    " **   * ",
    "*  *  * ",
    " **  *  ",
    "    *   ",
    "   *    ",
    "  *     ",
    "  *  ** ",
    " *  *  *",
    " *   ** ",
  },
  ["&"] =
  {
    "   **   ",
    "  *  *  ",
    "  *  *  ",
    "  * *   ",
    "   *    ",
    " ** * * ",
    "*    ** ",
    "*     * ",
    " ***** *",
  },
  ["A"] =
  {
    "    *   ",
    "   * *  ",
    "  *   * ",
    "  *   * ",
    " *     *",
    " *******",
    "*      *",
    "*      *",
    "*      *",
  },
  ["B"] =
  {
    "*****   ",
    "*    *  ",
    "*     * ",
    "*     * ",
    "******  ",
    "*     * ",
    "*     * ",
    "*    *  ",
    "*****   ",
  },
  ["C"] =
  {
    "  ****  ",
    " *    * ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
    " *    * ",
    "  ****  ",
  },
  ["D"] =
  {
    "****    ",
    "*   **  ",
    "*     * ",
    "*      *",
    "*      *",
    "*      *",
    "*     * ",
    "*   **  ",
    "****    ",
  },
  ["E"] =
  {
    "********",
    "*       ",
    "*       ",
    "*       ",
    "********",
    "*       ",
    "*       ",
    "*       ",
    "********",
  },
  ["F"] =
  {
    "******* ",
    "*       ",
    "*       ",
    "*       ",
    "******* ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
  },
  ["G"] =
  {
    " ****** ",
    "*      *",
    "*       ",
    "*       ",
    "*  *****",
    "*      *",
    "*      *",
    "*      *",
    " ****** ",
  },
  ["I"] =
  {
    "******* ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
    "******* ",
  },
  ["H"] =
  {
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "********",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
  },
  ["J"] =
  {
    " ****** ",
    "    *   ",
    "    *   ",
    "    *   ",
    "    *   ",
    "    *   ",
    "    *   ",
    "*   *   ",
    " ***    ",
  },
  ["K"] =
  {
    " *    * ",
    " *   *  ",
    " *  *   ",
    " * *    ",
    " **     ",
    " * *    ",
    " *  *   ",
    " *   *  ",
    " *    * ",
  },
  ["L"] =
  {
    "*       ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
    "******* ",
  },
  ["M"] =
  {
    "*      *",
    "**    **",
    "* *  * *",
    "*  **  *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
  },
  ["N"] =
  {
    "*      *",
    "**     *",
    "* *    *",
    "*  *   *",
    "*  *   *",
    "*   *  *",
    "*    * *",
    "*     **",
    "*      *",
  },
  ["O"] =
  {
    " ****** ",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    " ****** ",
  },
  ["P"] =
  {
    "******  ",
    "*     * ",
    "*      *",
    "*     * ",
    "******  ",
    "*       ",
    "*       ",
    "*       ",
    "*       ",
  },
  ["Q"] =
  {
    " ****** ",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*     * ",
    " *   *  ",
    "  * *  *",
    "   **** ",
  },
  ["R"] =
  {
    "*****   ",
    "*    *  ",
    "*     * ",
    "*     * ",
    "*   *   ",
    "* **    ",
    "*   *   ",
    "*    *  ",
    "*     * ",
  },
  ["S"] =
  {
    "  ***** ",
    " *     *",
    "*       ",
    " *      ",
    "  ***   ",
    "     ** ",
    "       *",
    "*      *",
    " ****** ",
  },
  ["T"] =
  {
    "******* ",
    "*  *  * ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
    "   *    ",
  },
  ["U"] =
  {
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    " *    * ",
    "  ****  ",
  },
  ["V"] =
  {
    "*      *",
    " *     *",
    " *     *",
    " *     *",
    "  *   * ",
    "  *  *  ",
    "  * *   ",
    "   *    ",
    "  *     ",
  },
  ["W"] =
  {
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*      *",
    "*  **  *",
    "*  **  *",
    " **  ** ",
    " *    * ",
  },
  ["X"] =
  {
    "*      *",
    " *     *",
    "  *   * ",
    "   * *  ",
    "    *   ",
    "   **   ",
    "  *  *  ",
    " *    * ",
    "*      *",
  },
  ["Y"] =
  {
    "*      *",
    " *     *",
    "  *   * ",
    "   * *  ",
    "    *   ",
    "    *   ",
    "    *   ",
    "    *   ",
    "    *   ",
  },
  ["Z"] =
  {
    "********",
    "       *",
    "      * ",
    "     *  ",
    "    *   ",
    "   *    ",
    "  *     ",
    " *      ",
    "********",
  },
  ["^"] =
  {
    "   **   ",
    "  *  *  ",
    " *    * ",
    "*      *",
    "        ",
    "        ",
    "        ",
    "        ",
    "        ",
  },
  [":"] =
  {
    "        ",
    "   **   ",
    "   **   ",
    "        ",
    "        ",
    "        ",
    "   **   ",
    "   **   ",
    "        ",
  },
  ["#"] =
  {
    "  *  *  ",
    "  *  *  ",
    "  *  *  ",
    " ****** ",
    "  *  *  ",
    " ****** ",
    "  *  *  ",
    "  *  *  ",
    "  *  *  ",
  },
  ["/"] =
  {
    "        ",
    "       *",
    "      * ",
    "     *  ",
    "    *   ",
    "   *    ",
    "  *     ",
    " *      ",
    "*       ",
  },
  ["("] =
  {
    "    *   ",
    "   *    ",
    "  *     ",
    " *      ",
    " *      ",
    " *      ",
    "  *     ",
    "   *    ",
    "    *   ",
  },
  [")"] =
  {
    "   *    ",
    "    *   ",
    "     *  ",
    "      * ",
    "      * ",
    "      * ",
    "     *  ",
    "    *   ",
    "   *    ",
  },
  ["{"] =
  {
    "    *** ",
    "   *    ",
    "   *    ",
    "  *     ",
    "**      ",
    "  *     ",
    "   *    ",
    "   *    ",
    "    *** ",
  },
  ["}"] =
  {
    " ***    ",
    "    *   ",
    "    *   ",
    "     *  ",
    "      **",
    "     *  ",
    "    *   ",
    "    *   ",
    " ***    ",
  },
  ["Unknown"] =
  {
    "********",
    "********",
    "***  ***",
    "***  ***",
    "**    **",
    "***  ***",
    "***  ***",
    "********",
    "********",
  },
}

local s_CharWidth = string.len(s_Char[0][1])
local s_CharHeight = #s_Char[0]

local s_CharData = {}
for char, raster_str in pairs(s_Char) do
  assert(#raster_str == s_CharHeight)
  local raster_data = {}
  for v, row in ipairs(raster_str) do
    local len = string.len(row)
    assert(len == s_CharWidth)
    raster_data[v] = {}
    for u = 1, len do
      local bit = string.sub(raster_str[v], u, u)
      raster_data[v][u] = (bit == "*")
    end
  end
  s_CharData[char] = raster_data
end

for digit = 0, 9 do
  s_CharData[tostring(digit)] = s_CharData[digit]
end
for _, letter in ipairs{"a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"} do
  s_CharData[letter] = s_CharData[string.upper(letter)]
end

-- NOTE: scale should be an integer
function Bitmap:DrawText(x, y, text, color, scale, spacing)
  scale = scale or DEFAULT_SCALE
  spacing = spacing or DEFAULT_SPACING
  
  local len = string.len(text)
  for i = 1, len do
    local char = string.sub(text, i, i)
    local raster = s_CharData[char] or s_CharData["Unknown"]
    for v, row in ipairs(raster) do
      for u, bit in ipairs(row) do
        if bit then
          local dest_x, dest_y = x + u - 1, y + v - 1
          if scale == 1 then
            self:SetPixel(dest_x, dest_y, color)
          else
            self:DrawBox(dest_x, dest_y, dest_x + scale - 1, dest_y + scale - 1, color)
          end
        end
      end
    end
    x = x + scale * s_CharWidth + spacing
  end
end

-- NOTE: scale should be an integer
function Bitmap:MeasureText(text, scale, spacing)
  scale = scale or DEFAULT_SCALE
  spacing = spacing or DEFAULT_SPACING
  
  local len = string.len(text)
  
  return len * scale * s_CharWidth + (len - 1) * spacing, scale * s_CharHeight
end